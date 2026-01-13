package opal

import kn "../katana"
import "../lucide"
import tw "../tailwind_colors"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:mem"
import "core:strconv"
import "core:strings"

Theme :: struct {
	text_gap:        f32,
	checkbox_size:   f32,
	label_text_size: f32,
	label_icon_size: f32,
	min_spacing:     f32,
	radius_small:    f32,
	radius_big:      f32,
	base_size:       [2]f32,
	animation_time:  f32,
	font_size_small: f32,
	font:            Font,
	monospace_font:  Font,
	icon_font:       Font,
	color:           Theme_Colors,
}

Theme_Colors :: struct {
	border:               Color,
	primary:              Color,
	primary_foreground:   Color,
	secondary:            Color,
	secondary_foreground: Color,
	secondary_strong:     Color,
	accent:               Color,
	background:           Color,
	base_strong:          Color,
	base_foreground:      Color,
}

theme_default :: proc() -> Theme {
	default_font :=
		kn.load_font_from_files(
			"../fonts/Lexend-Regular.png",
			"../fonts/Lexend-Regular.json",
		) or_else panic("Could not load default font")
	monospace_font :=
		kn.load_font_from_files(
			"../fonts/SpaceMono-Regular.png",
			"../fonts/SpaceMono-Regular.json",
		) or_else panic("Could not load monospace font")
	return Theme {
		text_gap = 4,
		checkbox_size = 18,
		label_text_size = 14,
		label_icon_size = 16,
		base_size = 12,
		min_spacing = 12,
		radius_small = 6,
		radius_big = 12,
		font_size_small = 14,
		color = {
			background = tw.NEUTRAL_100,
			base_strong = tw.NEUTRAL_300,
			accent = tw.BLUE_500,
			primary = tw.NEUTRAL_800,
			primary_foreground = tw.WHITE,
			secondary = tw.NEUTRAL_700,
			secondary_foreground = tw.NEUTRAL_950,
			secondary_strong = tw.NEUTRAL_600,
			border = tw.NEUTRAL_950,
			base_foreground = tw.BLACK,
		},
		font = default_font,
		monospace_font = monospace_font,
		icon_font = lucide.font,
	}
}

Checkbox_Descriptor :: struct {
	using base: Node_Descriptor,
	label:      string,
	value:      ^bool,
}

Checkbox_Result :: struct {
	node:    Maybe(^Node),
	toggled: bool,
}

add_checkbox :: proc(
	desc: ^Checkbox_Descriptor,
	loc := #caller_location,
) -> (
	result: Checkbox_Result,
) {
	assert(desc.value != nil)

	ctx := global_ctx

	push_id(hash_loc(loc))
	defer pop_id()

	node := begin_node(&{sizing = {fit = 1}, gap = 4, radius = 4, interactive = true}).?
	if node.is_active && !node.was_active {
		desc.value^ = !desc.value^
	}
	node_update_transition(node, 1, node.is_hovered, 0.1)
	node_update_transition(node, 0, desc.value^, 0.2)
	node.background = kn.fade(tw.SLATE_200, 0.2 * node.transitions[1])
	{
		add_node(
			&{
				sizing = {exact = ctx.theme.checkbox_size},
				radius = 4,
				stroke_width = 2,
				stroke = ctx.theme.color.border,
				text = string_from_rune(lucide.CHECK),
				font = &ctx.theme.icon_font,
				content_align = 0.5,
				font_size = ctx.theme.label_icon_size,
				foreground = kn.fade(ctx.theme.color.background, node.transitions[0]),
				background = kn.mix(
					node.transitions[0],
					ctx.theme.color.base_strong,
					ctx.theme.color.border,
				),
			},
		)
		add_node(
			&{
				sizing = {fit = 1},
				padding = {0, 0, 4, 0},
				text = desc.label,
				font_size = ctx.theme.label_text_size,
				foreground = ctx.theme.color.base_foreground,
			},
		)
	}
	end_node()
	return
}

Button_Variant :: enum {
	Primary,
	Outline,
	Ghost,
	Link,
}

Button_Descriptor :: struct {
	using base: Node_Descriptor,
	icon:       rune,
	label:      string,
	variant:    Button_Variant,
}

Button_Result :: struct {
	node:    Maybe(^Node),
	clicked: bool,
}

add_button :: proc(desc: ^Button_Descriptor, loc := #caller_location) -> (result: Button_Result) {
	assert(desc != nil)

	ctx := global_ctx

	push_id(hash_loc(loc))
	defer pop_id()

	desc.sizing = {
		fit = 1,
	}
	desc.interactive = true
	desc.radius = 4
	desc.background = global_ctx.theme.color.base_foreground

	color: Color
	switch desc.variant {
	case .Primary:
		color = tw.GREEN_600
	case .Outline:
		desc.stroke = tw.NEUTRAL_500
		desc.stroke_width = 1
	case .Ghost:
		color = tw.NEUTRAL_800
	case .Link:

	}

	result.node = begin_node(desc)
	{
		face_node := begin_node(
			&{
				sizing = {fit = 1},
				background = color,
				gap = 4,
				padding = {8, 4, 8, 4},
				radius = 4,
				content_align = 0.5,
			},
		).?
		{
			if desc.icon != 0 {
				add_node(
					&{
						foreground = ctx.theme.color.base_foreground,
						sizing = {fit = 1},
						font = &global_ctx.theme.icon_font,
						font_size = ctx.theme.label_icon_size,
						text = string_from_rune(desc.icon),
					},
				)
			}
			if desc.label != "" {
				add_node(
					&{
						foreground = ctx.theme.color.base_foreground,
						sizing = {fit = 1},
						font_size = ctx.theme.label_text_size,
						text = desc.label,
					},
				)
			}
		}
		end_node()
		if node, ok := result.node.?; ok {
			result.clicked = node.is_active && !node.was_active
			node_update_transition(node, 0, node.is_hovered, 0.15)
			node_update_transition(node, 1, node.is_active, 0.15)
			face_node.translate = -math.lerp(f32(2), f32(0), node.transitions[1])
		}
	}
	end_node()

	return
}

add_window_button :: proc(icon: rune, color: Color, loc := #caller_location) -> bool {
	ctx := global_ctx

	self := add_node(
		&{
			padding = 3,
			sizing = {fit = 1, max = INFINITY},
			text = string_from_rune(icon),
			font_size = 20,
			foreground = ctx.theme.color.base_foreground,
			font = &ctx.theme.icon_font,
			interactive = true,
		},
		loc = loc,
	).?
	node_update_transition(self, 0, self.is_hovered, 0.1)
	node_update_transition(self, 1, self.is_active, 0.1)
	self.style.background = fade(color, self.transitions[0])
	// self.style.foreground = mix(self.transitions[0], tw.WHITE, tw.NEUTRAL_900)
	assert(self != nil)
	return self.was_active && !self.is_active && self.is_hovered
}

Field_Descriptor :: struct {
	using base:      Node_Descriptor,
	placeholder:     string,
	format:          string,
	multiline:       bool,
	value_data:      rawptr,
	value_type_info: ^runtime.Type_Info,
}

Field_Response :: struct {
	node:          Maybe(^Node),
	was_changed:   bool,
	was_confirmed: bool,
}

add_field :: proc(desc: ^Field_Descriptor, loc := #caller_location) -> (res: Field_Response) {
	assert(desc != nil)

	ctx := global_ctx

	desc.background = tw.NEUTRAL_950
	desc.stroke = tw.NEUTRAL_500
	desc.font_size = 14
	desc.padding = 4
	desc.radius = 5
	desc.clip_content = true
	desc.interactive = true
	desc.sticky = true
	desc.enable_selection = true
	desc.wrapped = true
	desc.stroke_type = .Outer
	desc.content_align.y = 0.5
	if desc.format == "" {
		desc.format = "%v"
	}

	push_id(hash(loc))
	cont_node := begin_node(desc).?
	res.node = cont_node

	edit := cont_node.is_focused || cont_node.has_focused_child

	text_view := begin_text_view(
		{id = hash_loc(loc), show_cursor = true, editing = edit, container_node = cont_node},
	).?

	if edit {
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
			if desc.multiline {
				if control_down {
					res.was_confirmed = true
				}
			} else {
				res.was_confirmed = true
			}
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
		if !desc.multiline && (cmd in MULTILINE_COMMANDS) {
			cmd = .None
		}
		if cmd != .None {
			text_view_execute(text_view, cmd)
			if cmd in EDIT_COMMANDS {
				res.was_changed = true
			}
			draw_frames(1)
		}
	}

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

		if len(desc.placeholder) > 0 && len(text) == 0 {
			add_node(
				&{
					font = desc.font,
					font_size = desc.font_size,
					foreground = tw.NEUTRAL_500,
					text = desc.placeholder,
					sizing = {fit = 1},
				},
			)
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
					sizing = {fit = 1},
					interactive = true,
					enable_selection = true,
				},
			)
			pop_id()

			j += 1
			text = text[i:]
		}
	}

	end_text_view()

	// Cursor placeholder
	if edit && len(text_view.glyphs) == 0 {
		push_id(text_view.id)
		add_node(
			&{
				sizing = {max = INFINITY, exact = {2, 0}, grow = {0, 1}},
				background = get_text_cursor_color(),
			},
		)
		pop_id()
	}

	end_node()
	pop_id()

	node_update_transition(cont_node, 0, cont_node.is_hovered, 0.1)
	node_update_transition(cont_node, 1, edit, 0.1)
	cont_node.style.stroke = tw.LIME_500
	cont_node.style.stroke_width = 3 * cont_node.transitions[1]

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

do_menu_item :: proc(label: string, icon: rune, loc := #caller_location) {
	ctx := global_ctx

	push_id(hash(loc))

	self := begin_node(
		&{
			padding = {4, 4, 12, 4},
			sizing = {fit = 1, max = INFINITY, grow = {1, 0}},
			gap = 6,
			content_align = {0, 0.5},
			interactive = true,
			group = true,
			style = {radius = 6},
		},
	).?
	node_update_transition(self, 0, self.is_hovered, 0.1)
	node_update_transition(self, 1, self.is_active, 0.1)
	self.style.background = fade(
		tw.NEUTRAL_600,
		self.transitions[0] * 0.3 + self.transitions[1] * 0.3,
	)
	add_node(
		&{
			text = string_from_rune(icon),
			sizing = {fit = 1},
			style = {foreground = tw.NEUTRAL_300, font_size = 18, font = &ctx.theme.icon_font},
		},
	)
	add_node(
		&{text = label, sizing = {fit = 1}, style = {font_size = 14, foreground = tw.NEUTRAL_300}},
	)
	end_node()
	pop_id()
}

@(deferred_out = __do_menu)
do_menu :: proc(label: string, loc := #caller_location) -> bool {
	push_id(hash(loc))
	node := add_node(
		&{
			padding = 3,
			radius = 3,
			sizing = {fit = 1},
			text = label,
			font_size = 12,
			interactive = true,
		},
	).?
	node.style.background = fade(tw.NEUTRAL_600, (node.transitions[0] + node.transitions[1]) * 0.3)
	node.style.foreground =
		tw.BLUE_500 if (node.is_focused || node.has_focused_child) else tw.NEUTRAL_300
	node_update_transition(node, 1, node.is_active, 0)
	node_update_transition(node, 0, node.is_hovered, 0)
	if node.is_hovered && node.parent != nil && node.parent.has_focused_child {
		focus_node(node.id)
	}

	is_open := node.is_focused | node.has_focused_child

	if is_open {
		begin_node(
			&{
				is_root = true,
				shadow_size = 5,
				shadow_color = {0, 0, 0, 128},
				bounds = get_screen_box(),
				layer = 999,
				sizing = {fit = 1},
				padding = 4,
				radius = 5,
				background = tw.NEUTRAL_900,
				stroke = tw.NEUTRAL_600,
				stroke_width = 1,
				vertical = true,
			},
		)
	}

	pop_id()

	return is_open
}

@(private)
__do_menu :: proc(is_open: bool) {
	if is_open {
		end_node()
	}
}

Orientation :: enum {
	Horizontal,
	Vertical,
}

Resizer_Descriptor :: struct {
	using base:  Node_Descriptor,
	orientation: Orientation,
	value:       ^f32,
}

Resizer_Result :: struct {
	node: Maybe(^Node),
}

add_resizer :: proc(
	desc: ^Resizer_Descriptor,
	loc := #caller_location,
) -> (
	result: Resizer_Result,
) {
	assert(desc.value != nil)

	push_id(hash_loc(loc))
	defer pop_id()

	switch desc.orientation {
	case .Horizontal:
		desc.sizing.grow.x = 1
		desc.sizing.exact.y = 2
	case .Vertical:
		desc.sizing.grow.y = 1
		desc.sizing.exact.x = 2
	}

	desc.sizing.max = INFINITY
	desc.layer = 1
	desc.group = true
	desc.background = global_ctx.theme.color.border

	begin_node(desc)
	{
		node := add_node(
			&{
				absolute = true,
				sizing = {relative = {0, 1}, exact = {8, 0}},
				exact_offset = {-3, 0},
				interactive = true,
				sticky = true,
				cursor = Cursor.Resize_EW,
				data = desc.value,
				on_draw = proc(self: ^Node) {
					value := (^f32)(self.data)
					if self.is_active {
						value^ =
							self.parent.parent.box.hi.x -
							self.parent.parent.padding.z -
							self.parent.parent.gap -
							box_width(self.box) / 2 -
							global_ctx.mouse_position.x
					}
					center := box_center(self.box)
					color := kn.mix(
						self.transitions[0] * 0.5,
						global_ctx.theme.color.border,
						global_ctx.theme.color.accent,
					)
					box := Box{center - {4, 10}, center + {4, 10}}
					radius := box_width(self.box) / 2
					kn.add_box(box, radius, global_ctx.theme.color.background)
					kn.add_box_lines(box, 2, radius, color)
				},
			},
		).?
		node_update_transition(node, 0, node.is_hovered || node.is_active, 0.1)
		node_update_transition(node, 1, node.is_active, 0.2)
		result.node = node
	}
	end_node()

	return
}

