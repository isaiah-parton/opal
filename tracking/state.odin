package opal

import "base:runtime"
import "core:mem"
import "core:reflect"
import "core:time"

Object :: struct($T: typeid) {
	inner:        T,
	last_changed: time.Time,
}

object_borrow :: proc(self: ^Object($T)) -> ^T {
	self.last_changed = time.now()
	return self.inner
}

Array :: struct($T: typeid) {
	using object: Object([dynamic]T),
}

array_append :: proc(self: ^Array($T), elems: ..T) {
	append(object_borrow(self), ..elems)
}

array_ordered_remove :: proc(self: ^Array, index: int) {
	ordered_remove(object_borrow(self), index)
}

array_unordered_remove :: proc(self: ^Array, index: int) {
	unordered_remove(object_borrow(self), index)
}

array_remove_range :: proc(self: ^Array, from, to: int) {
	remove_range(object_borrow(self), from, to)
}

object_drop :: proc(self: ^Object) {
	free(self.data)
	self^ = {}
}

make_object_empty :: proc(type: typeid) -> Object {
	return Object {
		data = mem.alloc(size_of(type)) or_else nil,
		type = type,
		last_changed = time.now(),
	}
}

make_object :: proc(data: rawptr, type: typeid) -> Object {
	obj := Object {
		data         = mem.alloc(size_of(type)) or_else nil,
		type         = type,
		last_changed = time.now(),
	}
	clone(obj.data, data, type_info_of(type))
	return obj
}

Object_Manager :: struct {
	pool: map[rawptr]Object,
}

object_manager_cleanup :: proc(self: ^Object_Manager) {
	for key, &obj in self.pool {
		if time.since(obj.last_checked) > time.Minute {
			object_drop(&obj)
			delete_key(&self.pool, key)
		}
	}
}

object_manager_check :: proc(
	self: ^Object_Manager,
	data: rawptr,
	type: typeid,
) -> (
	changed: bool,
) {
	obj, ok := &self.pool[data]
	if !ok {
		obj = map_insert(&self.pool, data, make_object(data, type))
	}

	obj.last_checked = time.now()

	assert(obj.data != nil)

	if !reflect.equal(any{data, type}, any{obj.data, type}, recursion_level = 3) {
		obj.last_changed = time.now()
		changed = true
	}

	return
}

clone :: proc(target, source: rawptr, type_info: ^runtime.Type_Info) {

}

