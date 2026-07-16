## Efficient binary min-heap for A* pathfinding priority queue.
## Replaces O(N) linear scan of open set with O(log N) heap operations.
class_name BinaryHeap
extends RefCounted

var _heap: Array = []
var _key_to_index: Dictionary = {}

## Insert or update an element with a given key and priority.
## If the key already exists, updates its priority (re-heapifies if needed).
func push(key: String, priority: float) -> void:
	if _key_to_index.has(key):
		# Key exists — update priority and re-heapify
		var idx: int = _key_to_index[key]
		var old_priority: float = _heap[idx][1]
		_heap[idx][1] = priority
		
		if priority < old_priority:
			_bubble_up(idx)
		else:
			_bubble_down(idx)
	else:
		# New key — append and bubble up
		var idx: int = _heap.size()
		_heap.append([key, priority])
		_key_to_index[key] = idx
		_bubble_up(idx)

## Extract and return the minimum-priority element's key.
## Returns "" if heap is empty.
func pop() -> String:
	if _heap.is_empty():
		return ""
	
	var min_key: String = _heap[0][0]
	_key_to_index.erase(min_key)
	
	if _heap.size() == 1:
		_heap.clear()
		return min_key
	
	# Move last element to root and bubble down
	var last: Array = _heap.pop_back()
	_heap[0] = last
	_key_to_index[last[0]] = 0
	_bubble_down(0)
	
	return min_key

## Check if a key exists in the heap.
func has(key: String) -> bool:
	return _key_to_index.has(key)

## Check if heap is empty.
func is_empty() -> bool:
	return _heap.is_empty()

## Get the number of elements in the heap.
func size() -> int:
	return _heap.size()

func _bubble_up(idx: int) -> void:
	while idx > 0:
		var parent_idx: int = (idx - 1) / 2
		if _heap[idx][1] >= _heap[parent_idx][1]:
			break
		_swap(idx, parent_idx)
		idx = parent_idx

func _bubble_down(idx: int) -> void:
	var size: int = _heap.size()
	while true:
		var smallest: int = idx
		var left: int = 2 * idx + 1
		var right: int = 2 * idx + 2
		
		if left < size and _heap[left][1] < _heap[smallest][1]:
			smallest = left
		if right < size and _heap[right][1] < _heap[smallest][1]:
			smallest = right
		
		if smallest == idx:
			break
		
		_swap(idx, smallest)
		idx = smallest

func _swap(a: int, b: int) -> void:
	var temp: Array = _heap[a]
	_heap[a] = _heap[b]
	_heap[b] = temp
	_key_to_index[_heap[a][0]] = a
	_key_to_index[_heap[b][0]] = b
