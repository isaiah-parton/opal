package components

import ".."
import "base:runtime"
import "core:strings"

add_input_raw :: proc(data: rawptr, type_info: ^runtime.Type_Info) {
	node := add_node(
		&{
			background = tw.NEUTRAL_950,
			stroke = tw.NEUTRAL_500,
			stroke_width = 1,
			clip_content = true,
			text = app.edited_text,
			font_size = 16,
			padding = 4,
			radius = 3,
			foreground = tw.NEUTRAL_50,
			fit = {0, 1},
			size = {200, 0},
			max_size = INFINITY,
			grow = {false, true},
			enable_edit = true,
			enable_selection = true,
			is_widget = true,
			stroke_type = .Outer,
			content_align = {0, 0.5},
		},
	).?
	node_update_transition(node, 0, node.is_hovered, 0.1)
	node_update_transition(node, 1, node.is_focused, 0.1)
	node.style.stroke = tw.LIME_500
	node.style.stroke_width = 3 * node.transitions[1]
	if node.was_changed {
		replace_input_content(data, type_info, strings.to_string(node.builder))
	}
}

add_input_any :: proc(value: any) {

}

replace_input_content :: proc(
	data: rawptr,
	type_info: ^runtime.Type_Info,
	text: string,
	allocator := context.allocator,
) -> bool {
	#partial switch v in type_info.variant {
	case (runtime.Type_Info_String):
		if v.is_cstring {
			cstring_pointer := (^cstring)(data)
			delete(cstring_pointer^)
			cstring_pointer^ = strings.clone_to_cstring(text, allocator = allocator)
		} else {
			string_pointer := (^string)(data)
			delete(string_pointer^)
			string_pointer^ = strings.clone(text, allocator = allocator)
		}
	case (runtime.Type_Info_Float):
		switch type_info.id {
		case f16:
			(^f16)(data)^ = cast(f16)strconv.parse_f32(text) or_return
		case f32:
			(^f32)(data)^ = strconv.parse_f32(text) or_return
		case f64:
			(^f64)(data)^ = strconv.parse_f64(text) or_return
		}
	case (runtime.Type_Info_Integer):
		switch type_info.id {
		case int:
			(^int)(data)^ = strconv.parse_int(text) or_return
		case i8:
			(^i8)(data)^ = cast(i8)strconv.parse_i64(text) or_return
		case i16:
			(^i16)(data)^ = cast(i16)strconv.parse_i64(text) or_return
		case i32:
			(^i32)(data)^ = cast(i32)strconv.parse_i64(text) or_return
		case i64:
			(^i64)(data)^ = strconv.parse_i64(text) or_return
		case i128:
			(^i128)(data)^ = strconv.parse_i128(text) or_return
		case uint:
			(^uint)(data)^ = strconv.parse_uint(text) or_return
		case u8:
			(^u8)(data)^ = cast(u8)strconv.parse_u64(text) or_return
		case u16:
			(^u16)(data)^ = cast(u16)strconv.parse_u64(text) or_return
		case u32:
			(^u32)(data)^ = cast(u32)strconv.parse_u64(text) or_return
		case u64:
			(^u64)(data)^ = strconv.parse_u64(text) or_return
		case u128:
			(^u128)(data)^ = strconv.parse_u128(text) or_return
		case:
			return false
		}
	case (runtime.Type_Info_Enum):
		for name, i in v.names {
			if text == name {
				mem.copy(data, &v.values[i], v.base.size)
				break
			}
		}
	case:
		break
	}
	return true
}
