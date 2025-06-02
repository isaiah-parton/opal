package components

import ".."
import kn "../../katana"
import tw "../tailwind_colors"
import "base:runtime"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:strconv"
import "core:strings"

Field_Descriptor :: struct {
	using base:      opal.Node_Descriptor,
	placeholder:     string,
	format:          string,
	value_data:      rawptr,
	value_type_info: ^runtime.Type_Info,
}

Field_Response :: struct {
	was_changed:   bool,
	was_confirmed: bool,
}

make_field_descriptor :: proc(data: rawptr, type_info: ^runtime.Type_Info) -> Field_Descriptor {
	return {
		background = tw.NEUTRAL_950,
		stroke = tw.NEUTRAL_500,
		stroke_width = 1,
		font_size = 16,
		padding = 4,
		radius = 3,
		clip_content = true,
		interactive = true,
		inherit_state = true,
		wrapped = true,
		stroke_type = .Outer,
		value_data = data,
		value_type_info = type_info,
		cursor = .Text,
		format = "%v",
	}
}

add_field :: proc(desc: ^Field_Descriptor, loc := #caller_location) -> (res: Field_Response) {
	using opal
	cont_node := begin_node(desc).?

	edit := cont_node.is_focused || cont_node.has_focused_child

	text_view := begin_text_view({id = hash_loc(loc), show_cursor = true, editing = edit}).?

	{
		text: string
		if edit {
			text = strings.to_string(text_view.builder)
		} else {
			text = fmt.tprintf(
				desc.format,
				any{data = desc.value_data, id = desc.value_type_info.id},
			)
		}

		if desc.placeholder != "" && len(text) == 0 {
			push_id(hash(loc))
			add_node(
				&{
					font = desc.font,
					font_size = desc.font_size,
					foreground = tw.NEUTRAL_500,
					text = desc.placeholder,
					fit = 1,
				},
			)
			pop_id()
		}

		j := 1

		for len(text) > 0 {
			i := strings.index_byte(text, ' ')
			if i == -1 {
				i = len(text)
			} else {
				i += 1
			}

			push_id(j)
			add_node(
				&{
					font = desc.font,
					font_size = desc.font_size,
					foreground = tw.WHITE,
					text = text[:i],
					fit = 1,
					interactive = true,
					enable_selection = true,
					cursor = .Text,
				},
			)
			pop_id()

			j += 1
			text = text[i:]
		}

	}

	end_node()
	end_text_view()

	node_update_transition(cont_node, 0, cont_node.is_hovered, 0.1)
	node_update_transition(cont_node, 1, cont_node.is_focused, 0.1)
	cont_node.style.stroke = tw.LIME_500
	cont_node.style.stroke_width = 3 * cont_node.transitions[1]

	ctx := global_ctx

	if cont_node.is_focused {
		cmd: Command
		control_down := key_down(.Left_Control) || key_down(.Right_Control)
		shift_down := key_down(.Left_Shift) || key_down(.Right_Shift)
		if control_down {
			if key_pressed(.A) do cmd = .Select_All
			if key_pressed(.C) do cmd = .Copy
			if key_pressed(.V) do cmd = .Paste
			if key_pressed(.X) do cmd = .Cut
			if key_pressed(.Z) do cmd = .Undo
			if key_pressed(.Y) do cmd = .Redo
		}
		if len(ctx.text_input) > 0 {
			for char, c in ctx.text_input {
				text_view_insert_runes(text_view, {char})
				draw_frames(1)
				res.was_changed = true
			}
		}
		if key_pressed(.Backspace) do cmd = .Delete_Word_Left if control_down else .Backspace
		if key_pressed(.Delete) do cmd = .Delete_Word_Right if control_down else .Delete
		if key_pressed(.Enter) {
			cmd = .New_Line
			// if self.is_multiline {
			// 	if control_down {
			// 		res.was_confirmed = true
			// 	}
			// } else {
			// 	res.was_confirmed = true
			// }
		}
		if key_pressed(.Left) {
			if shift_down do cmd = .Select_Word_Left if control_down else .Select_Left
			else do cmd = .Word_Left if control_down else .Left
		}
		if key_pressed(.Right) {
			if shift_down do cmd = .Select_Word_Right if control_down else .Select_Right
			else do cmd = .Word_Right if control_down else .Right
		}
		if key_pressed(.Up) {
			if shift_down do cmd = .Select_Up
			else do cmd = .Up
		}
		if key_pressed(.Down) {
			if shift_down do cmd = .Select_Down
			else do cmd = .Down
		}
		if key_pressed(.Home) {
			cmd = .Select_Line_Start if control_down else .Line_Start
		}
		if key_pressed(.End) {
			cmd = .Select_Line_End if control_down else .Line_End
		}
		// if !self.is_multiline && (cmd in MULTILINE_COMMANDS) {
		// 	cmd = .None
		// }
		if cmd != .None {
			text_view_execute(text_view, cmd)
			if cmd in EDIT_COMMANDS {
				res.was_changed = true
			}
			draw_frames(1)
		}
	}

	if res.was_changed {
		field_output(desc.value_data, desc.value_type_info, strings.to_string(text_view.builder))
	}

	return
}

field_output :: proc(
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

// Perform text editing
// TODO: Implement up/down movement
/*
	if self.enable_edit {

	}
	*/
