package opal

import "base:runtime"
import "core:mem"
import "core:reflect"
import "core:strings"
import "core:time"

Object :: struct {
	data:         rawptr,
	type:         typeid,
	last_changed: time.Time,
	last_checked: time.Time,
}

object_drop :: proc(self: ^Object) {
	recursively_delete(self.data, type_info_of(self.type))
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
	recursively_compare_and_clone(obj.data, data, type_info_of(type))
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

	if !recursively_compare_and_clone(obj.data, data, type_info_of(type)) {
		obj.last_changed = time.now()
		changed = true
	}

	return
}

recursively_delete :: proc(data: rawptr, type_info: ^runtime.Type_Info) {
	type_info := runtime.type_info_base(type_info)

	#partial switch v in type_info.variant {
	case (runtime.Type_Info_Struct):
		for i in 0 ..< v.field_count {
			recursively_delete(rawptr(uintptr(data) + v.offsets[i]), v.types[i])
		}
	case (runtime.Type_Info_String):
		if v.is_cstring {
			delete_cstring((^cstring)(data)^)
		} else {
			delete_string((^string)(data)^)
		}
	}
}

// Recursively compares two data structures of the same type, cloning source values to the target on mismatch and returning whether any differences were found.
recursively_compare_and_clone :: proc(
	target, source: rawptr,
	type_info: ^runtime.Type_Info,
	max_depth := 3,
	depth := 0,
) -> (
	changed: bool,
) {
	type_info := runtime.type_info_base(type_info)

	#partial switch v in type_info.variant {
	case (runtime.Type_Info_Struct):
		for i in 0 ..< v.field_count {
			changed |= recursively_compare_and_clone(
				rawptr(uintptr(target) + v.offsets[i]),
				rawptr(uintptr(source) + v.offsets[i]),
				v.types[i],
				max_depth,
				depth + 1,
			)
		}
	case (runtime.Type_Info_String):
		if v.is_cstring {
			target_cstring := (^cstring)(target)
			source_cstring := (^cstring)(source)
			if target_cstring^ != source_cstring^ {
				target_cstring^ = strings.clone_to_cstring(string(source_cstring^))
				changed = true
			}
		} else {
			target_string := (^string)(target)
			source_string := (^string)(source)
			if target_string^ != source_string^ {
				target_string^ = strings.clone(source_string^)
				changed = true
			}
		}
	case:
		if mem.compare_ptrs(target, source, type_info.size) != 0 {
			mem.copy(target, source, type_info.size)
			changed = true
		}
	}
	return
}

VIEW_STACK_HEIGHT :: 128

View_Manager :: struct {
	dict:  map[Id]View,
	stack: Stack(^View, VIEW_STACK_HEIGHT),
}

view_manager_cleanup :: proc(self: ^View_Manager) {
	for key, &view in self.dict {
		if view.dead {
			view_drop(&view)
		} else {
			view.dead = true
		}
	}
}

View_Ref :: Maybe(^View)

View :: struct {
	id:     Id,
	dead:   bool,
	dirty:  bool,
	object: Maybe(Object),
	nodes:  []^Node,
}

view_drop :: proc(self: ^View) {

}

view_begin :: proc(self: ^View) {

}

view_end :: proc(self: ^View) {

}

View_Build_Proc :: #type proc()

// Builds once on its own, then further updates have to be triggered
add_lazy_view :: proc(ref: ^View_Ref, build_proc: View_Build_Proc, loc := #caller_location) {

}

// Diffs state every time its called and rebuilds if anything changed
add_reactive_view :: proc(state: any, build_proc: View_Build_Proc, loc := #caller_location) {

}

// Only builds once
add_static_view :: proc(build_proc: View_Build_Proc, loc := #caller_location) {

}

