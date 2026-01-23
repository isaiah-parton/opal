package opal

import kn "../katana"
import "../lucide"
import tw "../tailwind_colors"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:mem"
import "core:strconv"
import "core:strings"
import "core:unicode"

Theme :: struct {
	text_gap:        f32,
	checkbox_size:   f32,
	label_text_size: f32,
	label_icon_size: f32,
	min_spacing:     f32,
	radius_small:    f32,
	radius_big:      f32,
	base_size:       [2]f32,
	border_width:    f32,
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
	selection_background: Color,
	selection_foreground: Color,
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
		border_width = 2,
		label_text_size = 14,
		label_icon_size = 16,
		base_size = 12,
		min_spacing = 12,
		radius_small = 8,
		radius_big = 16,
		font_size_small = 14,
		color = {
			background = tw.AMBER_100,
			base_strong = kn.color_from_rgba(
				kn.color_from_hsla_array(
					kn.hsla_from_rgba(kn.rgba_from_color(tw.AMBER_200)) * [4]f32{1, 0.5, 1, 1},
				),
			),
			accent = tw.PURPLE_400,
			primary = tw.EMERALD_500,
			primary_foreground = tw.WHITE,
			secondary = tw.NEUTRAL_700,
			secondary_foreground = tw.NEUTRAL_950,
			secondary_strong = tw.NEUTRAL_600,
			border = tw.GRAY_900,
			base_foreground = tw.BLACK,
			selection_background = tw.INDIGO_500,
			selection_foreground = tw.BLACK,
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

	node := begin_node(
		&{sizing = {fit = 1, max = INFINITY}, gap = 4, radius = 4, interactive = true},
	).?
	if node.is_active && !node.was_active {
		desc.value^ = !desc.value^
	}
	node_update_transition(node, 0, desc.value^, 0.1)
	node_update_transition(node, 1, node.is_hovered, 0.1)
	node_update_transition(node, 2, node.is_active, 0.1)
	node.background = kn.fade(ctx.theme.color.base_strong, node.transitions[1])
	{
		add_node(
			&{
				sizing = {exact = ctx.theme.checkbox_size},
				radius = 4,
				stroke_width = 2,
				stroke = ctx.theme.color.border,
				text = string_from_rune(lucide.X),
				font = &ctx.theme.icon_font,
				content_align = 0.5,
				font_size = ctx.theme.label_icon_size,
				foreground = kn.fade(ctx.theme.color.base_strong, node.transitions[0]),
				background = kn.mix(
					node.transitions[0],
					ctx.theme.color.background,
					ctx.theme.color.border,
				),
				transform_origin = 0.5,
				scale = math.lerp(f32(1), f32(0.9), node.transitions[2]),
			},
		)
		add_node(
			&{
				sizing = {fit = 1, max = INFINITY},
				padding = {0, 0, 4, 0},
				text = desc.label,
				font = &ctx.theme.font,
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
		max = INFINITY,
	}
	desc.interactive = true
	desc.radius = 4
	desc.background = ctx.theme.color.base_foreground

	face_node_desc := Node_Descriptor {
		sizing = {fit = 1, max = INFINITY},
		stroke_width = 2,
		stroke = ctx.theme.color.border,
		gap = 4,
		padding = {8, 4, 8, 4},
		radius = 4,
		content_align = 0.5,
	}

	depth: f32 = 2
	switch desc.variant {
	case .Primary:
		face_node_desc.background = ctx.theme.color.primary
	case .Outline:
		face_node_desc.background = ctx.theme.color.background
	case .Ghost:
		face_node_desc.background = ctx.theme.color.base_strong
		face_node_desc.stroke_width = 0
		desc.background = mix(0.5, ctx.theme.color.base_strong, tw.BLACK)
	case .Link:
		face_node_desc.background = ctx.theme.color.background
		face_node_desc.stroke_width = 0
		depth = 0
		desc.cursor = .Pointer
		desc.background = tw.TRANSPARENT
	}

	result.node = begin_node(desc)
	{
		face_node := begin_node(&face_node_desc).?
		{
			if desc.icon != 0 {
				add_node(
					&{
						foreground = ctx.theme.color.base_foreground,
						sizing = {fit = 1, max = INFINITY},
						font = &global_ctx.theme.icon_font,
						font_size = ctx.theme.label_icon_size,
						text = string_from_rune(desc.icon),
						underline = desc.variant == .Link && result.node.?.is_hovered,
					},
				)
			}
			if desc.label != "" {
				add_node(
					&{
						foreground = ctx.theme.color.base_foreground,
						sizing = {fit = 1, max = INFINITY},
						font = &ctx.theme.font,
						font_size = ctx.theme.label_text_size,
						text = desc.label,
						underline = desc.variant == .Link && result.node.?.is_hovered,
					},
				)
			}
		}
		end_node()
		if node, ok := result.node.?; ok {
			result.clicked = node.is_active && !node.was_active
			node_update_transition(node, 0, node.is_hovered, 0.15)
			node_update_transition(node, 1, node.is_active, 0.1)
			face_node.translate = {0, -math.lerp(depth, f32(0), node.transitions[1])}
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

	desc.stroke = ctx.theme.color.border
	desc.stroke_width = 2
	if desc.font == nil {
		desc.font = &ctx.theme.font
	}
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

	text: string

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

		if edit {
			text = strings.to_string(text_view.builder)
		} else {
			text = fmt.tprintf(
				desc.format,
				any{data = desc.value_data, id = desc.value_type_info.id},
			)
		}

		s := text

		i := 1

		for len(s) > 0 {
			push_id(i)
			i += 1

			line_end := strings.index_byte(s, '\n')
			if line_end == -1 {
				line_end = len(s)
			} else {
				line_end += 1
			}
			line := s[:line_end]

			begin_node(&{wrapped = true, sizing = {fit = 1, max = INFINITY, grow = {1, 0}}})
			pop_id()
			{
				for len(line) > 0 {
					push_id(i)
					i += 1

					word_end := -1

					starts_with_white_space := unicode.is_white_space(rune(line[0]))

					for s, i in line {
						is_white_space := unicode.is_white_space(rune(s))
						if is_white_space != starts_with_white_space {
							word_end = i
							break
						}
					}

					if word_end == -1 {
						word_end = len(line)
					}

					word := line[:word_end]

					add_node(
						&{
							foreground = ctx.theme.color.base_foreground,
							sizing = {fit = 1, max = INFINITY},
							text = word,
							font = desc.font,
							font_size = desc.font_size,
							interactive = true,
							enable_selection = true,
						},
					)
					pop_id()

					line = line[word_end:]
				}
			}
			end_node()

			s = s[line_end:]
		}

		if len(text) == 0 {
			add_node(
				&{
					font = desc.font,
					font_size = desc.font_size,
					foreground = ctx.theme.color.base_foreground,
					sizing = {fit = 1, max = INFINITY},
					interactive = true,
					enable_selection = true,
				},
			)
		}
	}

	end_text_view()

	if len(desc.placeholder) > 0 && len(text) == 0 {
		add_node(
			&{
				font = desc.font,
				font_size = desc.font_size,
				foreground = kn.fade(ctx.theme.color.base_foreground, 0.5),
				text = desc.placeholder,
				sizing = {fit = 1, max = INFINITY},
			},
		)
	}

	end_node()
	pop_id()

	node_update_transition(cont_node, 0, cont_node.is_hovered, 0.1)
	node_update_transition(cont_node, 1, edit, 0.1)
	cont_node.background = mix(
		cont_node.transitions[1],
		ctx.theme.color.base_strong,
		ctx.theme.color.background,
	)

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
		ctx.theme.color.base_strong,
		self.transitions[0] * 0.3 + self.transitions[1] * 0.3,
	)
	add_node(
		&{
			text = string_from_rune(icon),
			sizing = {fit = 1},
			style = {
				foreground = ctx.theme.color.base_foreground,
				font_size = 18,
				font = &ctx.theme.icon_font,
			},
		},
	)
	add_node(
		&{
			text = label,
			sizing = {fit = 1},
			style = {font_size = 14, foreground = ctx.theme.color.base_foreground},
		},
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

Progress_Bar_Descriptor :: struct {
	using base: Node_Descriptor,
	color:      Maybe(Color),
	value:      f32,
}

add_progress_bar :: proc(desc: ^Progress_Bar_Descriptor) -> (result: Maybe(^Node)) {
	desc.sizing.exact = {200, global_ctx.theme.base_size.y}
	desc.style.stroke = global_ctx.theme.color.border
	desc.style.stroke_width = 2
	desc.style.background = global_ctx.theme.color.background
	desc.style.foreground = desc.color.? or_else global_ctx.theme.color.accent
	desc.on_draw = proc(self: ^Node) {
		self.radius = box_height(self.box) / 2
		kn.add_box(self.box, self.radius, node_convert_paint_variant(self, self.style.background))
		kn.push_scissor(kn.make_box(self.box, self.radius))
		kn.add_box(
			{
				self.box.lo,
				{math.lerp(self.box.lo.x, self.box.hi.x, self.transitions[0]), self.box.hi.y},
			},
			0,
			self.style.foreground,
		)
		kn.pop_scissor()
		kn.add_box_lines(self.box, self.style.stroke_width, self.radius, self.style.stroke)
	}
	result = add_node(desc)
	result.?.transitions[0] = desc.value
	return
}

Color_Picker_Descriptor :: struct {
	using base: Node_Descriptor,
	value:      ^Color,
}

Color_Picker_Result :: struct {
	node:    ^Node,
	changed: bool,
}

Color_Picker_State :: struct {
	hsla:  [4]f32,
	value: ^Color,
}

barycentric :: proc(point, a, b, c: [2]f32) -> (u, v: f32) {
	d := c - a
	e := b - a
	f := point - a
	dd := linalg.dot(d, d)
	ed := linalg.dot(e, d)
	fd := linalg.dot(f, d)
	ee := linalg.dot(e, e)
	fe := linalg.dot(f, e)
	denom := dd * ee - ed * ed
	u = (ee * fd - ed * fe) / denom
	v = (dd * fe - ed * fd) / denom
	return
}

nearest_point_on_line :: proc(a, b, p: [2]f32) -> [2]f32 {
	ap := p - a
	ab_dir := b - a
	dot := ap.x * ab_dir.x + ap.y * ab_dir.y
	if dot < 0 do return a
	ab_len_sqr := ab_dir.x * ab_dir.x + ab_dir.y * ab_dir.y
	if dot > ab_len_sqr do return b
	return a + ab_dir * dot / ab_len_sqr
}

nearest_point_in_triangle :: proc(a, b, c, p: [2]f32) -> [2]f32 {
	proj_ab := nearest_point_on_line(a, b, p)
	proj_bc := nearest_point_on_line(b, c, p)
	proj_ca := nearest_point_on_line(c, a, p)
	dist2_ab := linalg.length2(p - proj_ab)
	dist2_bc := linalg.length2(p - proj_bc)
	dist2_ca := linalg.length2(p - proj_ca)
	m := linalg.min(dist2_ab, linalg.min(dist2_bc, dist2_ca))
	if m == dist2_ab do return proj_ab
	if m == dist2_bc do return proj_bc
	return proj_ca
}

triangle_contains_point :: proc(a, b, c, p: [2]f32) -> bool {
	b1 := ((p.x - b.x) * (a.y - b.y) - (p.y - b.y) * (a.x - b.x)) < 0
	b2 := ((p.x - c.x) * (b.y - c.y) - (p.y - c.y) * (b.x - c.x)) < 0
	b3 := ((p.x - a.x) * (c.y - a.y) - (p.y - a.y) * (c.x - a.x)) < 0
	return (b1 == b2) && (b2 == b3)
}

triangle_barycentric :: proc(a, b, c, p: [2]f32) -> (u, v, w: f32) {
	v0 := b - a
	v1 := c - a
	v2 := p - a
	denom := v0.x * v1.y - v1.x * v0.y
	v = (v2.x * v1.y - v1.x * v2.y) / denom
	w = (v0.x * v2.y - v2.x * v0.y) / denom
	u = 1 - v - w
	return
}

draw_checkerboard_pattern :: proc(box: Box, size: [2]f32, primary, secondary: kn.Color) {
	kn.add_box(box, paint = primary)
	for x in 0 ..< int(math.ceil(box_width(box) / size.x)) {
		for y in 0 ..< int(math.ceil(box_height(box) / size.y)) {
			if (x + y) % 2 == 0 {
				pos := box.lo + [2]f32{f32(x), f32(y)} * size
				kn.add_box({pos, linalg.min(pos + size, box.hi)}, paint = secondary)
			}
		}
	}
}

TRIANGLE_STEP :: math.TAU / 3

make_a_triangle :: proc(center: [2]f32, angle: f32, radius: f32) -> (a, b, c: [2]f32) {
	a = center + {math.cos(angle), math.sin(angle)} * radius
	b = center + {math.cos(angle - TRIANGLE_STEP), math.sin(angle - TRIANGLE_STEP)} * radius
	c = center + {math.cos(angle + TRIANGLE_STEP), math.sin(angle + TRIANGLE_STEP)} * radius
	return
}

add_color_picker :: proc(
	desc: ^Color_Picker_Descriptor,
	loc := #caller_location,
) -> (
	result: Color_Picker_Result,
	ok: bool,
) {
	if desc.value == nil {
		return
	}

	push_id(hash_loc(loc))
	defer pop_id()

	desc.sizing.fit = 1
	desc.sizing.max = INFINITY
	desc.gap = global_ctx.theme.min_spacing
	desc.vertical = true
	desc.on_destroy = proc(self: ^Node) {
		if self.owned_data != nil {
			free(self.owned_data)
		}
	}

	result.node = begin_node(desc).? or_return
	if result.node.owned_data == nil {
		result.node.owned_data = new_clone(
			Color_Picker_State{hsla = kn.hsva_from_rgba(kn.rgba_from_color(desc.value^))},
		)
	}
	state := (^Color_Picker_State)(result.node.owned_data)
	state.value = desc.value
	{
		color_wheel_node := add_node(
			&{
				interactive = true,
				sizing = {exact = 200},
				sticky = true,
				on_draw = proc(self: ^Node) {
					assert(self.parent != nil)
					state := (^Color_Picker_State)(self.parent.owned_data)
					assert(state != nil)
					assert(state.value != nil)

					size := min(box_width(self.box), box_height(self.box))
					outer_radius := size / 2
					inner_radius := outer_radius * 0.75
					center := box_center(self.box)
					angle := state.hsla.x * math.RAD_PER_DEG

					if self.is_active {
						delta_to_mouse := global_ctx.mouse_position - center
						if linalg.length(global_ctx.mouse_click_position - center) > inner_radius {
							state.hsla.x =
								math.atan2(delta_to_mouse.y, delta_to_mouse.x) / math.RAD_PER_DEG
							if state.hsla.x < 0 {
								state.hsla.x += 360
							}
						} else {
							point := global_ctx.mouse_position
							point_a, point_b, point_c := make_a_triangle(
								center,
								angle,
								inner_radius,
							)
							if !triangle_contains_point(point_a, point_b, point_c, point) {
								point = nearest_point_in_triangle(point_a, point_b, point_c, point)
							}
							u, v, w := triangle_barycentric(point_a, point_b, point_c, point)
							state.hsla.z = clamp(1 - v, 0, 1)
							state.hsla.y = clamp(u / state.hsla.z, 0, 1)
						}

						rgba := kn.rgba_from_hsva(state.hsla)
						state.value.rgb = kn.color_from_rgba(rgba).xyz
					}

					kn.add_circle_lines(
						center,
						outer_radius + 2,
						width = (outer_radius - inner_radius) + 4,
						paint = global_ctx.theme.color.border,
					)
					kn.add_circle_lines(
						center,
						outer_radius,
						width = (outer_radius - inner_radius),
						paint = kn.make_wheel_gradient(center),
					)

					point_a, point_b, point_c := make_a_triangle(
						center,
						state.hsla.x * math.RAD_PER_DEG,
						inner_radius - 2,
					)

					kn.add_polygon(
						{point_a, point_b, point_c},
						paint = kn.make_tri_gradient(
							{point_a, point_b, point_c},
							{
								kn.color_from_rgba(kn.rgba_from_hsva({state.hsla.x, 1, 1, 1})),
								kn.BLACK,
								kn.WHITE,
							},
						),
					)
					kn.add_polygon_lines(
						{point_a, point_b, point_c},
						2,
						paint = global_ctx.theme.color.border,
					)

					point := linalg.lerp(
						linalg.lerp(point_c, point_a, clamp(state.hsla.y, 0, 1)),
						point_b,
						clamp(1 - state.hsla.z, 0, 1),
					)
					r: f32 = 9 if (self.is_active) else 7
					kn.add_circle(
						point,
						r,
						paint = kn.color_from_rgba(
							kn.rgba_from_hsva({state.hsla.x, state.hsla.y, state.hsla.z, 1}),
						),
					)
					kn.add_circle_lines(
						point,
						r,
						2,
						paint = kn.BLACK if state.hsla.z > 0.5 else kn.WHITE,
					)
				},
			},
		).?

		alpha_slider_node := add_node(
			&{
				stroke = global_ctx.theme.color.border,
				stroke_width = global_ctx.theme.border_width,
				interactive = true,
				sticky = true,
				sizing = {exact = {0, 30}, grow = {1, 0}, max = INFINITY},
				data = desc.value,
				on_draw = proc(self: ^Node) {
					color := (^Color)(self.data)
					assert(color != nil)

					i := int(self.vertical)
					j := 1 - i

					if self.is_active {
						color.a = u8(
							clamp(
								(global_ctx.mouse_position[i] - self.box.lo[i]) /
								(self.box.hi[i] - self.box.lo[i]),
								0,
								1,
							) *
							255,
						)
					}

					draw_checkerboard_pattern(
						self.box,
						(self.box.hi[j] - self.box.lo[j]) / 2,
						tw.GRAY_400,
						tw.GRAY_600,
					)
					time := clamp(f32(color.a) / 255, 0, 1)
					pos := self.box.lo[i] + (self.box.hi[i] - self.box.lo[i] - 6) * time
					if i == 0 {
						kn.add_box(
							self.box,
							paint = kn.make_linear_gradient(
								self.box.lo,
								{self.box.hi.x, self.box.lo.y},
								kn.fade(color^, 0.0),
								color^,
							),
						)
						kn.add_box_lines(
							box_floored({{pos, self.box.lo.y}, {pos + 6, self.box.hi.y}}),
							2,
							paint = global_ctx.theme.color.base_foreground,
						)
					}
					kn.add_box_lines(
						self.box,
						self.style.stroke_width,
						self.style.radius,
						self.style.stroke,
					)
				},
			},
		).?

	}
	end_node()

	return
}

