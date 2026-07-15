## LAN server browser — separate from NetManager on purpose: this speaks raw
## broadcast UDP, not the high-level `multiplayer`/RPC API net_manager.gd's
## doc comment claims exclusive ownership of. Two independent roles, both on
## DISCOVERY_PORT (NetManager.DEFAULT_PORT + 1, so it can't collide with the
## actual ENet game port):
##
##  - Announcing (host side): broadcast a small JSON blob describing the
##    lobby every BROADCAST_INTERVAL seconds, from start_announcing() (call
##    once NetManager.host() has succeeded) until stop_announcing() (leaving
##    the lobby or starting the match — a running match isn't joinable, so it
##    shouldn't show up in anyone's browser).
##  - Browsing (client side): listen for those blobs from start_browsing()
##    until stop_browsing(), tracking last-seen-per-host so a closed/crashed
##    host's entry ages out on its own (STALE_TIMEOUT) rather than sticking
##    around forever.
##
## start_screen.gd owns the lifecycle calls (it already owns every other
## lobby-flow transition) and filters+renders `servers_updated`'s payload.
class_name LanDiscovery
extends Node

signal servers_updated(servers: Dictionary) ## "ip:port" -> {name, capital_name, player_count, max_players, port, ip}

const DISCOVERY_PORT := NetManager.DEFAULT_PORT + 1
const BROADCAST_INTERVAL := 1.0
const STALE_TIMEOUT := 3.0

var _announce_socket: PacketPeerUDP
var _announce_payload: PackedByteArray
var _announce_timer: float = 0.0

var _browse_socket: PacketPeerUDP
var _servers: Dictionary = {}

func _process(delta: float) -> void:
	if _announce_socket != null:
		_announce_timer += delta
		if _announce_timer >= BROADCAST_INTERVAL:
			_announce_timer = 0.0
			_announce_socket.put_packet(_announce_payload)
	if _browse_socket != null:
		_drain_incoming()
		_prune_stale()

## --- announcing (host) -------------------------------------------------------

func start_announcing(info: Dictionary) -> void:
	_announce_socket = PacketPeerUDP.new()
	_announce_socket.set_broadcast_enabled(true)
	_announce_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_announce_timer = BROADCAST_INTERVAL ## send the first frame immediately, not after a full interval
	update_announce_info(info)

## Called whenever roster size changes so a browsing peer's player count
## stays live without waiting for the next scheduled broadcast tick.
func update_announce_info(info: Dictionary) -> void:
	_announce_payload = JSON.stringify(info).to_utf8_buffer()

func stop_announcing() -> void:
	_announce_socket = null

## --- browsing (client) --------------------------------------------------------

func start_browsing() -> void:
	_browse_socket = PacketPeerUDP.new()
	var err := _browse_socket.bind(DISCOVERY_PORT)
	if err != OK:
		_browse_socket = null
		return
	_servers.clear()
	servers_updated.emit(_servers)

func stop_browsing() -> void:
	if _browse_socket != null:
		_browse_socket.close()
	_browse_socket = null
	_servers.clear()

func _drain_incoming() -> void:
	var changed := false
	while _browse_socket.get_available_packet_count() > 0:
		var packet := _browse_socket.get_packet()
		var ip := _browse_socket.get_packet_ip()
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not (parsed is Dictionary) or not parsed.has("port"):
			continue ## malformed or non-Hexis traffic sharing the port
		var key := "%s:%d" % [ip, int(parsed["port"])]
		parsed["ip"] = ip
		parsed["last_seen"] = Time.get_ticks_msec() / 1000.0
		_servers[key] = parsed
		changed = true
	if changed:
		servers_updated.emit(_servers)

func _prune_stale() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var changed := false
	for key in _servers.keys():
		if now - _servers[key]["last_seen"] > STALE_TIMEOUT:
			_servers.erase(key)
			changed = true
	if changed:
		servers_updated.emit(_servers)
