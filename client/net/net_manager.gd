## Godot high-level multiplayer (ENet) transport + lobby, listen-server
## topology (the host is also a player). Owns everything that touches
## `multiplayer`/RPC in the whole project — sim/ stays engine/network-free
## per 07-data-architecture.md section 8, and lockstep_driver.gd (the piece
## that actually schedules commands into the sim) only ever talks to this
## class's signals/methods, never to ENet directly.
##
## Roster assignment: only the host hands out owner_ids ("p0".."pN", host is
## always p0), because only the host can guarantee two clients connecting at
## the same instant don't race for the same id. A client learns its own
## owner_id (and everyone else's) from _sync_roster, broadcast by the host
## any time the roster changes.
##
## Command/checksum wire format: CommandProcessor args are String or HexCoord
## (see command_queue.gd) — HexCoord isn't RPC-serializable on its own, so
## _encode_arg/_decode_arg tag it as "@hex:q,r" (a prefix no real id ever
## starts with) rather than needing a per-verb argument schema here.
class_name NetManager
extends Node

signal roster_updated(roster: Dictionary) ## peer_id (int) -> {owner_id, name, capital_name}
signal match_starting(world_seed: int, player_count: int, roster: Dictionary)
## commands: Array[{"verb": String, "args": Array, "seq": int}], possibly
## empty — lockstep_driver.gd needs one of these per peer per tick (even when
## a peer has nothing to say) to know it's safe to resolve that tick at all.
signal input_frame_received(exec_tick: int, commands: Array, owner_id: String)
## sections: names of MatchState.to_dict() top-level keys whose hash didn't
## match across peers (see MatchState.section_checksums()) — narrows a
## desync down to "which piece of state", not just "state diverged".
signal desync_detected(tick: int, sections: Array)
## Host-only: a non-host peer's on-desync dump (main.gd's var_to_str'd
## {diverged_sections, command_log}) arrived for saving alongside the host's
## own local dump — see send_desync_dump().
signal desync_dump_received(tick: int, owner_id: String, dump_text: String)
signal connection_failed(reason: String)

const DEFAULT_PORT := 24545
const MAX_PLAYERS := 6
const HEX_ARG_PREFIX := "@hex:"
## ENet's own connect timeout is up to ~30s (silently dropped packets, no
## ICMP refusal on most setups) — way too long to sit on "Connecting..." when
## there's simply no server listening. We give up sooner and report failure.
const JOIN_TIMEOUT_SEC := 5.0

var is_host: bool = false
var local_owner_id: String = ""
var roster: Dictionary = {} ## peer_id -> {"owner_id": String, "name": String, "capital_name": String}

var _pending_name: String = ""
var _pending_capital_name: String = ""
var _checksums_by_tick: Dictionary = {} ## tick -> {peer_id: checksum}

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func host(port: int, player_name: String, capital_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	local_owner_id = "p0"
	roster[1] = {"owner_id": "p0", "name": player_name, "capital_name": capital_name}
	roster_updated.emit(roster)
	return OK

func join(ip: String, port: int, player_name: String, capital_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	_pending_name = player_name
	_pending_capital_name = capital_name
	get_tree().create_timer(JOIN_TIMEOUT_SEC).timeout.connect(_on_join_timeout.bind(peer))
	return OK

## Fires JOIN_TIMEOUT_SEC after join() regardless of outcome; the `peer` bind
## lets it recognize a stale timer from an earlier/abandoned join attempt
## (multiplayer.multiplayer_peer will have moved on) and no-op instead of
## misreporting a since-succeeded or since-replaced connection.
func _on_join_timeout(peer: ENetMultiplayerPeer) -> void:
	if multiplayer.multiplayer_peer != peer:
		return
	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		connection_failed.emit("no response from server")
		leave()

## Called by the start screen when the name/capital-name fields are edited
## while already connected. Host applies directly and rebroadcasts; a client
## asks the host to apply it (only the host is allowed to mutate `roster`,
## same as _register_player) via _request_rename.
func rename_self(player_name: String, capital_name: String) -> void:
	if is_host:
		if roster.has(1):
			roster[1]["name"] = player_name
			roster[1]["capital_name"] = capital_name
			_sync_roster.rpc(roster)
	else:
		_request_rename.rpc_id(1, player_name, capital_name)

## Closes the connection and resets lobby state — used by the start screen's
## Back button and when leaving a finished/aborted match.
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_host = false
	local_owner_id = ""
	roster.clear()
	_checksums_by_tick.clear()

## Host-only — call once the lobby has enough players. Broadcasts the seed
## and final roster so every peer builds an identical MatchState (see
## client/main.gd's MapGenerator.generate(player_count, world_seed, ...)).
func start_match(world_seed: int) -> void:
	if not is_host:
		return
	_compact_owner_ids()
	_receive_match_start.rpc(world_seed, roster.size(), roster)

## Reassigns owner_ids to a contiguous "p0".."p(N-1)" run (ordered by peer id,
## so the host — always peer id 1 — stays "p0"). Belt-and-suspenders against
## world gen (base_site_selector.gd) and _build_owner_visuals (main.gd), which
## both derive owner ids by looping range(player_count): a disconnect earlier
## in the lobby can leave a gap (host=p0, p1 leaves, p2 remains) that neither
## loop would ever produce, silently stranding the p2 player with no base.
func _compact_owner_ids() -> void:
	var peer_ids := roster.keys()
	peer_ids.sort()
	for i in range(peer_ids.size()):
		roster[peer_ids[i]]["owner_id"] = "p%d" % i

## Broadcasts this peer's commands for a future tick to every peer (host
## included, via call_local) — see lockstep_driver.gd for exec_tick/commands.
func send_input_frame(exec_tick: int, commands: Array, owner_id: String) -> void:
	var encoded: Array = commands.map(func(c): return {"verb": c["verb"], "args": c["args"].map(_encode_arg), "seq": c["seq"]})
	_receive_input_frame.rpc(exec_tick, encoded, owner_id)

## Reports this peer's per-section state checksums for `tick` to the host for
## comparison. Not a broadcast — only the host aggregates and decides if peers
## diverged. `sections` is MatchState.section_checksums()'s result (section
## name -> hash) rather than one combined int, so a mismatch can be narrowed
## down to which section actually differs.
func send_checksum(tick: int, sections: Dictionary) -> void:
	if is_host:
		_report_checksum(tick, sections, 1)
	else:
		_report_checksum.rpc_id(1, tick, sections)

## Ships this peer's on-desync dump text to the host so both sides' files
## land on one machine instead of needing a manual copy off the other
## player's PC. No-op on the host itself — it already wrote its own dump
## locally (see main.gd's _dump_state_for_debug).
func send_desync_dump(tick: int, owner_id: String, dump_text: String) -> void:
	if is_host:
		return
	_receive_desync_dump.rpc_id(1, tick, owner_id, dump_text)

func player_count() -> int:
	return roster.size()

## Best-effort LAN address for the "give this to your friends" hint in the
## lobby — first non-loopback IPv4 reported by the OS. Good enough for the
## same-LAN case this game targets; doesn't attempt NAT/port-forwarding
## discovery for players on different networks.
static func local_ip_hint() -> String:
	for addr in IP.get_local_addresses():
		if addr.find(":") == -1 and not addr.begins_with("127."):
			return addr
	return "127.0.0.1"

## --- connection lifecycle ---------------------------------------------------
## (Host learns of a new client via _register_player below, not
## peer_connected — the client still needs to send its display name before
## it belongs in the roster.)

func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	if roster.has(id):
		roster.erase(id)
		roster_updated.emit(roster)

func _on_connected_to_server() -> void:
	_register_player.rpc_id(1, _pending_name, _pending_capital_name)

func _on_connection_failed(reason: String = "connection failed") -> void:
	connection_failed.emit(reason)

func _on_server_disconnected() -> void:
	connection_failed.emit("host disconnected")
	leave()

## --- RPCs --------------------------------------------------------------------

## Client -> host. Assigns the next free "p<n>" id and rebroadcasts the roster.
@rpc("any_peer", "call_remote", "reliable")
func _register_player(player_name: String, capital_name: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	roster[sender] = {
		"owner_id": "p%d" % _lowest_free_owner_index(),
		"name": _dedupe(player_name, _others_field("name", sender)),
		"capital_name": _dedupe(capital_name, _others_field("capital_name", sender)),
	}
	_sync_roster.rpc(roster)

## Lowest "p<n>" suffix not already taken in the roster — unlike roster.size(),
## this can't hand out a duplicate after an earlier disconnect leaves a gap
## (e.g. host=p0, p1 leaves, p2 remains: size() is 2, which p2 already has).
func _lowest_free_owner_index() -> int:
	var taken: Dictionary = {}
	for entry in roster.values():
		taken[int(String(entry["owner_id"]).trim_prefix("p"))] = true
	var index := 0
	while taken.has(index):
		index += 1
	return index

## Client -> host, in response to editing the name/capital fields mid-lobby.
@rpc("any_peer", "call_remote", "reliable")
func _request_rename(player_name: String, capital_name: String) -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not roster.has(sender):
		return
	roster[sender]["name"] = _dedupe(player_name, _others_field("name", sender))
	roster[sender]["capital_name"] = _dedupe(capital_name, _others_field("capital_name", sender))
	_sync_roster.rpc(roster)

## Every other peer's current value for `field` — "other" so renaming
## yourself back to your own unchanged value doesn't get treated as a
## collision with yourself.
func _others_field(field: String, exclude_peer: int) -> Array:
	var values: Array = []
	for peer_id in roster:
		if peer_id != exclude_peer:
			values.append(roster[peer_id][field])
	return values

## Host-only uniqueness: two players both leaving name/capital_name at their
## defaults ("Unnamed Player"/"Unnamed Base") would otherwise collide, and
## nothing downstream (roster display, per-owner capital display_name in
## main.gd) distinguishes same-named entries. Appends the lowest free " N"
## suffix rather than rejecting the value outright, since this runs on every
## keystroke via rename_self() and rejecting would fight the player's typing.
static func _dedupe(candidate: String, taken: Array) -> String:
	if not taken.has(candidate):
		return candidate
	var n := 1
	while taken.has("%s %d" % [candidate, n]):
		n += 1
	return "%s %d" % [candidate, n]

## Host -> all. Replaces the full roster (small lobby, full-replace is simpler
## and cheap enough versus diffing) and lets each peer resolve its own
## local_owner_id from its own peer id.
@rpc("authority", "call_local", "reliable")
func _sync_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	var my_id := multiplayer.get_unique_id()
	if roster.has(my_id):
		local_owner_id = roster[my_id]["owner_id"]
	roster_updated.emit(roster)

@rpc("authority", "call_local", "reliable")
func _receive_match_start(world_seed: int, player_count_value: int, final_roster: Dictionary) -> void:
	roster = final_roster
	var my_id := multiplayer.get_unique_id()
	if roster.has(my_id):
		local_owner_id = roster[my_id]["owner_id"]
	match_starting.emit(world_seed, player_count_value, roster)

@rpc("any_peer", "call_local", "reliable")
func _receive_input_frame(exec_tick: int, encoded_commands: Array, owner_id: String) -> void:
	var commands: Array = encoded_commands.map(func(c): return {"verb": c["verb"], "args": c["args"].map(_decode_arg), "seq": c["seq"]})
	input_frame_received.emit(exec_tick, commands, owner_id)

## Host-only aggregation: once every roster'd peer has reported `tick`,
## compare — any mismatch is a desync, broadcast so every client can halt
## rather than silently drift further apart. Compares per-section rather than
## one combined value so the broadcast can name exactly which section(s)
## diverged (see MatchState.section_checksums()).
@rpc("any_peer", "call_remote", "reliable")
func _report_checksum(tick: int, sections: Dictionary, _sender_override: int = -1) -> void:
	if not is_host:
		return
	var sender := _sender_override if _sender_override != -1 else multiplayer.get_remote_sender_id()
	if not _checksums_by_tick.has(tick):
		_checksums_by_tick[tick] = {}
	_checksums_by_tick[tick][sender] = sections

	if _checksums_by_tick[tick].size() < roster.size():
		return
	var per_sender: Array = _checksums_by_tick[tick].values()
	var mismatched_sections: Array = []
	for key in per_sender[0]:
		for i in range(1, per_sender.size()):
			if per_sender[i].get(key) != per_sender[0][key]:
				mismatched_sections.append(key)
				break
	_checksums_by_tick.erase(tick)
	if not mismatched_sections.is_empty():
		_desync_detected.rpc(tick, mismatched_sections)

@rpc("authority", "call_local", "reliable")
func _desync_detected(tick: int, sections: Array) -> void:
	desync_detected.emit(tick, sections)

## Client -> host only, in response to a desync — see send_desync_dump().
@rpc("any_peer", "call_remote", "reliable")
func _receive_desync_dump(tick: int, owner_id: String, dump_text: String) -> void:
	if not is_host:
		return
	desync_dump_received.emit(tick, owner_id, dump_text)

## --- wire encoding -----------------------------------------------------------

static func _encode_arg(value: Variant) -> Variant:
	return HEX_ARG_PREFIX + value.to_key() if value is HexCoord else value

static func _decode_arg(value: Variant) -> Variant:
	if value is String and value.begins_with(HEX_ARG_PREFIX):
		return HexCoord.from_key(value.substr(HEX_ARG_PREFIX.length()))
	return value
