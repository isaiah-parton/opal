package opal

import "core:fmt"
import "core:io"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode"
import "core:unicode/utf8"

Command_Set :: distinct bit_set[Command;u32]

Command :: enum u32 {
	None,
	Undo,
	Redo,
	New_Line, // multi-lines
	Cut,
	Copy,
	Paste,
	Select_All,
	Backspace,
	Delete,
	Delete_Word_Left,
	Delete_Word_Right,
	Left,
	Right,
	Up, // multi-lines
	Down, // multi-lines
	Word_Left,
	Word_Right,
	Start,
	End,
	Line_Start,
	Line_End,
	Select_Left,
	Select_Right,
	Select_Up, // multi-lines
	Select_Down, // multi-lines
	Select_Word_Left,
	Select_Word_Right,
	Select_Start,
	Select_End,
	Select_Line_Start,
	Select_Line_End,
}

MULTILINE_COMMANDS :: Command_Set{.New_Line, .Up, .Down, .Select_Up, .Select_Down}
EDIT_COMMANDS :: Command_Set {
	.New_Line,
	.Delete,
	.Delete_Word_Left,
	.Delete_Word_Right,
	.Backspace,
	.Cut,
	.Paste,
	.Undo,
	.Redo,
}

Translation :: enum u32 {
	Start,
	End,
	Left,
	Right,
	Up,
	Down,
	Word_Left,
	Word_Right,
	Word_Start,
	Word_End,
	Soft_Line_Start,
	Soft_Line_End,
}

//
// Text selection is functional at least for ASCII, just figure out a solution for a more acceptable visual representation of selection
//

//
Text_View_Descriptor :: struct {
	id:             Id,
	show_cursor:    bool,
	editing:        bool,
	container_node: ^Node,
}

//
// A 'view' of a bunch of text in the UI. An abstraction that manages multiple nodes with text content.
//
// Any interactive node with text will be included in only the top text on the stack at the time.
//
Text_View :: struct {
	using desc:       Text_View_Descriptor,

	// Text length in bytes
	byte_length:      int,

	// Hovered glyph index
	hover_index:      int,

	// Selection in glyph indices
	selection:        [2]int,

	//
	last_selection:   [2]int,

	// Anchor for word selection
	anchor:           int,

	//
	cursor_box:       Box,

	// Interactive nodes with text
	nodes:            [dynamic]^Node,

	// All glyphs, interactive or not
	glyphs:           [dynamic]Glyph,

	// Selection shape
	selection_boxes:  [dynamic]Box,

	// Text
	builder:          strings.Builder,

	// Active text container node
	active_container: Id,

	// Active
	active:           bool,

	// Kill flag
	dead:             bool,
}

text_view_translate :: proc(self: ^Text_View, pos: int, t: Translation) -> int {
	is_continuation_byte :: proc(b: byte) -> bool {
		return b >= 0x80 && b < 0xc0
	}

	is_space :: proc(b: byte) -> bool {
		return b == ' ' || b == '\t' || b == '\n'
	}

	buf := self.builder.buf[:]

	pos := pos
	pos = clamp(pos, 0, len(buf))

	switch t {
	case .Start:
		pos = 0
	case .End:
		pos = len(buf)
	case .Left:
		pos -= 1
		for pos >= 0 && is_continuation_byte(buf[pos]) {
			pos -= 1
		}
	case .Right:
		pos += 1
		for pos < len(buf) && is_continuation_byte(buf[pos]) {
			pos += 1
		}
	case .Up:
	// pos = self.up_index
	case .Down:
	// pos = self.down_index
	case .Word_Left:
		for pos > 0 && is_space(buf[pos - 1]) {
			pos -= 1
		}
		for pos > 0 && !is_space(buf[pos - 1]) {
			pos -= 1
		}
	case .Word_Right:
		for pos < len(buf) && !is_space(buf[pos]) {
			pos += 1
		}
		for pos < len(buf) && is_space(buf[pos]) {
			pos += 1
		}
	case .Word_Start:
		for pos > 0 && !is_space(buf[pos - 1]) {
			pos -= 1
		}
	case .Word_End:
		for pos < len(buf) && !is_space(buf[pos]) {
			pos += 1
		}
	case .Soft_Line_Start:
	// pos = self.line_start
	case .Soft_Line_End:
	// pos = self.line_end
	}
	return clamp(pos, 0, len(buf))
}

text_view_move_to :: proc(self: ^Text_View, t: Translation) {
	if t == .Left && text_view_has_selection(self) {
		selection := text_view_get_ordered_selection(self)
		self.selection = selection[0]
	} else if t == .Right && text_view_has_selection(self) {
		selection := text_view_get_ordered_selection(self)
		self.selection = selection[1]
	} else {
		pos := text_view_translate(self, self.selection[0], t)
		self.selection = {pos, pos}
	}
}

text_view_select_to :: proc(self: ^Text_View, t: Translation) {
	self.selection[1] = text_view_translate(self, self.selection[1], t)
}

text_view_delete_to :: proc(self: ^Text_View, t: Translation) {
	if text_view_has_selection(self) {
		text_view_delete_selection(self)
	} else {
		lo := self.selection[0]
		hi := text_view_translate(self, lo, t)
		lo, hi = min(lo, hi), max(lo, hi)
		remove_range(&self.builder.buf, lo, hi)
		self.selection = {lo, lo}
	}
}

text_view_delete_selection :: proc(self: ^Text_View) {
	selection := text_view_get_ordered_selection(self)
	remove_range(&self.builder.buf, selection[0], selection[1])
	self.selection = selection[0]
}

text_view_cut :: proc(self: ^Text_View) -> bool {
	if text_view_copy_to_clipboard(self) {
		lo, hi :=
			min(self.selection[0], self.selection[1]), max(self.selection[0], self.selection[1])
		text_view_delete_selection(self)
		return true
	}
	return false
}

text_view_copy_to_clipboard :: proc(self: ^Text_View) -> bool {
	set_clipboard(text_view_get_selection_string(self))
	return true
}

text_view_paste_from_clipboard :: proc(self: ^Text_View) -> bool {
	assert(global_ctx.on_get_clipboard != nil)
	str := global_ctx.on_get_clipboard(global_ctx.callback_data) or_return
	a: bool
	str, a = strings.replace_all(str, "\t", " ") // this should never allocate
	text_view_insert(self, str)
	if a {
		delete(str)
	}
	return true
}

text_view_has_selection :: proc(self: ^Text_View) -> bool {
	return self.selection[0] != self.selection[1]
}

text_view_insert_runes :: proc(self: ^Text_View, runes: []rune) {
	if text_view_has_selection(self) {
		text_view_delete_selection(self)
	}
	offset := self.selection[0]
	for r in runes {
		b, w := utf8.encode_rune(r)
		text := string(b[:w])
		inject_at(&self.builder.buf, offset, text)
		offset += w
	}
	self.selection = {offset, offset}
}

text_view_insert :: proc(self: ^Text_View, data: string) {
	if text_view_has_selection(self) {
		text_view_delete_selection(self)
	}
	inject_at(&self.builder.buf, self.selection[0], data)
	self.selection += len(data)
}

text_view_execute :: proc(self: ^Text_View, cmd: Command) {
	switch cmd {
	case .None: /**/
	case .Undo:
	// editor_undo(self, &self.undo, &self.redo)
	case .Redo:
	// editor_undo(self, &self.redo, &self.undo)
	case .New_Line:
		text_view_insert_runes(self, {'\n'})
	case .Cut:
		text_view_cut(self)
	case .Copy:
		text_view_copy_to_clipboard(self)
	case .Paste:
		text_view_paste_from_clipboard(self)
	case .Select_All:
		self.selection = {len(self.builder.buf), 0}
	case .Backspace:
		text_view_delete_to(self, .Left)
	case .Delete:
		text_view_delete_to(self, .Right)
	case .Delete_Word_Left:
		text_view_delete_to(self, .Word_Left)
	case .Delete_Word_Right:
		text_view_delete_to(self, .Word_Right)
	case .Left:
		text_view_move_to(self, .Left)
	case .Right:
		text_view_move_to(self, .Right)
	case .Up:
		text_view_move_to(self, .Up)
	case .Down:
		text_view_move_to(self, .Down)
	case .Word_Left:
		text_view_move_to(self, .Word_Left)
	case .Word_Right:
		text_view_move_to(self, .Word_Right)
	case .Start:
		text_view_move_to(self, .Start)
	case .End:
		text_view_move_to(self, .End)
	case .Line_Start:
		text_view_move_to(self, .Soft_Line_Start)
	case .Line_End:
		text_view_move_to(self, .Soft_Line_End)
	case .Select_Left:
		text_view_select_to(self, .Left)
	case .Select_Right:
		text_view_select_to(self, .Right)
	case .Select_Up:
		text_view_select_to(self, .Up)
	case .Select_Down:
		text_view_select_to(self, .Down)
	case .Select_Word_Left:
		text_view_select_to(self, .Word_Left)
	case .Select_Word_Right:
		text_view_select_to(self, .Word_Right)
	case .Select_Start:
		text_view_select_to(self, .Start)
	case .Select_End:
		text_view_select_to(self, .End)
	case .Select_Line_Start:
		text_view_select_to(self, .Soft_Line_Start)
	case .Select_Line_End:
		text_view_select_to(self, .Soft_Line_End)
	}
}

text_view_on_mouse_move :: proc(self: ^Text_View, mouse_position: [2]f32) {
	min_dist: [2]f32 = INFINITY
	closest_y: f32

	text_view_validate_selection_candidate :: proc(self: ^Text_View, node: ^Node) -> bool {
		return(
			(node.parent != nil &&
				(node.parent.is_hovered || self.active_container == node.parent.id)) ||
			node.is_hovered \
		)
	}

	for node in self.nodes {
		if !text_view_validate_selection_candidate(self, node) {
			continue
		}

		dist_y := abs((node.text_origin.y + node.text_size.y / 2) - mouse_position.y)

		if dist_y < min_dist.y {
			min_dist.y = dist_y
			closest_y = node.text_origin.y
		}
	}

	for node in self.nodes {
		if !text_view_validate_selection_candidate(self, node) || node.text_origin.y != closest_y {
			continue
		}

		for glyph, glyph_index in node.glyphs {
			dist := abs((node.text_origin.x + glyph.offset.x) - mouse_position.x)

			if dist < min_dist.x {
				min_dist.x = dist
				self.hover_index = glyph_index + node.text_glyph_index
				self.active_container = node.parent.id if node.parent != nil else 0
			}
		}

		if len(node.glyphs) > 0 {
			dist := abs((node.text_origin.x + node.text_size.x) - mouse_position.x)

			if dist < min_dist.x {
				min_dist.x = dist
				self.hover_index = len(node.glyphs) + node.text_glyph_index
				self.active_container = node.parent.id if node.parent != nil else 0
			}
		}
	}
}

text_view_get_glyph_position :: proc(self: ^Text_View, index: int) -> [2]f32 {
	glyph := self.glyphs[index]
	return node_get_glyph_position(glyph.node, index - glyph.node.text_glyph_index)
}

text_view_on_mouse_down :: proc(self: ^Text_View, index: int) {
	self.selection = self.hover_index
	self.anchor = self.hover_index
}

text_view_when_mouse_down :: proc(self: ^Text_View, index: int) {

	is_separator :: proc(r: rune) -> bool {
		return !unicode.is_alpha(r) && !unicode.is_number(r)
	}

	data := strings.to_string(self.builder)

	last_selection := self.selection

	switch index {
	case 0:
		self.selection[1] = self.hover_index

	case 1:
		allow_precision := self.hover_index != self.selection[0]

		if self.hover_index < self.anchor {
			self.selection[1] =
				self.hover_index if (allow_precision && is_separator(rune(data[self.hover_index]))) else max(0, strings.last_index_proc(data[:min(self.hover_index, len(data))], is_separator) + 1)

			self.selection[0] = strings.index_proc(data[self.anchor:], is_separator)

			if self.selection[0] == -1 {
				self.selection[0] = len(data)
			} else {
				self.selection[0] += self.anchor
			}
		} else {
			self.selection[0] = max(
				0,
				strings.last_index_proc(data[:self.anchor], is_separator) + 1,
			)

			self.selection[1] =
				0 if (allow_precision && is_separator(rune(data[self.hover_index - 1]))) else strings.index_proc(data[self.hover_index:], is_separator)

			if self.selection[1] == -1 {
				self.selection[1] = len(data)
			} else {
				self.selection[1] += self.hover_index
			}
		}

	case 2:
		self.selection = {0, len(self.glyphs)}
	}
}

text_view_get_ordered_selection :: proc(self: ^Text_View) -> [2]int {
	if self.selection[0] > self.selection[1] {
		return self.selection.yx
	}
	return self.selection
}

text_view_update_cursor_box :: proc(self: ^Text_View) {
	cursor_index := self.selection[1]

	if len(self.glyphs) > 0 && cursor_index >= 0 && cursor_index <= len(self.glyphs) {
		glyph := self.glyphs[min(cursor_index, len(self.glyphs) - 1)]

		assert(glyph.node != nil)

		line_height := glyph.node.font.line_height * glyph.node.font_size

		top_left := node_get_glyph_position(glyph.node, cursor_index - glyph.node.text_glyph_index)

		if cursor_index == len(self.glyphs) {
			// top_left.x += glyph.advance * glyph.node.font_size
		}

		self.cursor_box = {{top_left.x, top_left.y}, {top_left.x + 2, top_left.y + line_height}}
	}
}

text_view_collect_range :: proc(self: ^Text_View, from, to: int, w: io.Writer) {
	if from >= to {
		return
	}

	for node in self.nodes {
		indices := [2]int {
			clamp(from - node.text_byte_index, 0, len(node.text)),
			clamp(to - node.text_byte_index, 0, len(node.text)),
		}

		if indices[0] == indices[1] {
			continue
		}

		io.write_string(w, node.text[indices[0]:indices[1]])
	}
}

text_view_get_selection_string :: proc(
	self: ^Text_View,
	allocator := context.allocator,
) -> string {
	selection := text_view_get_ordered_selection(self)

	b := strings.builder_make(allocator = allocator)

	text_view_collect_range(
		self,
		self.glyphs[selection[0]].index if selection[0] < len(self.glyphs) else self.byte_length,
		self.glyphs[selection[1]].index if selection[1] < len(self.glyphs) else self.byte_length,
		strings.to_writer(&b),
	)

	return strings.to_string(b)
}

text_view_update_viewport :: proc(self: ^Text_View) {
	if self.container_node == nil {
		return
	}

	node := self.container_node

	// Make sure to clip the cursor
	padded_box := node_get_padded_box(node)
	left := max(0, padded_box.lo.x - self.cursor_box.lo.x)
	top := max(0, padded_box.lo.y - self.cursor_box.lo.y)
	right := max(0, self.cursor_box.hi.x - padded_box.hi.x)
	bottom := max(0, self.cursor_box.hi.y - padded_box.hi.y)
	node.has_clipped_child |= max(left, right) > 0
	node.has_clipped_child |= max(top, bottom) > 0

	// Scroll to bring cursor into view
	node.target_scroll.x += right - left
	node.target_scroll.y += bottom - top
}

text_view_update_hightlight_shape :: proc(self: ^Text_View) {
	selection := text_view_get_ordered_selection(self)

	clear(&self.selection_boxes)

	for node in self.nodes {
		box := node_get_text_selection_box(node)
		if box_is_real(box) {
			append(&self.selection_boxes, Box{box.lo - 1, box.hi + 1})
		}
	}

	join_overlapping_boxes :: proc(box: ^Box, excluded_index: int, array: ^[dynamic]Box) {
		for len(array) > 0 {
			found := false
			for &other, i in array {
				if i == excluded_index {
					continue
				}
				left := max(-0.5, other.lo.x - box.hi.x)
				right := max(-0.5, other.hi.x - box.lo.x)
				if box.lo.y == other.lo.y && box.hi.y == other.hi.y && max(left, right) >= 0 {
					box.lo.x = min(other.lo.x, box.lo.x)
					box.hi.x = max(other.hi.x, box.hi.x)
					ordered_remove(array, i)
					found = true
				}
			}
			if !found {
				break
			}
		}
	}

	for &box, i in self.selection_boxes {
		join_overlapping_boxes(&box, i, &self.selection_boxes)
	}

	// for box in boxes {
	// 	append(
	// 		&box.points,
	// 		Point{pos = box.box.lo, idx = i},
	// 		Point{pos = {box.box.hi.x, box.box.lo.y}, idx = i},
	// 		Point{pos = box.box.hi, idx = i},
	// 		Point{pos = {box.box.lo.x, box.box.hi.y}, idx = i},
	// 	)
	// }

	// start: [2]f32 = math.F32_MAX

	// for &point, i in points {
	// 	overlapped: bool
	// 	for j := 0; j < len(boxes); j += 1 {
	// 		if j == point.idx {
	// 			continue
	// 		}
	// 		box := boxes[j]

	// 		if point.pos.y >= box.lo.y && point.pos.y <= box.hi.y {
	// 			if point.pos.x == box.lo.x || point.pos.x == box.hi.x {
	// 				overlapped = true
	// 				break
	// 			} else if point.pos.x > box.lo.x && point.pos.x < box.hi.x {
	// 				top := max(0, point.pos.y - box.lo.y)
	// 				bottom := max(0, box.hi.y - point.pos.y)
	// 				if top < bottom {
	// 					point.pos.y -= top
	// 				} else {
	// 					point.pos.y += bottom
	// 				}
	// 			}
	// 		}
	// 	}
	// 	if overlapped {
	// 		ordered_remove(&points, i)
	// 	} else {
	// 		if point.pos.y < start.y || (point.pos.y == start.y && point.pos.x < start.x) {
	// 			start = point.pos
	// 		}
	// 	}
	// }

	// for &point in points {
	// 	point.angle = math.atan2(point.pos.y - start.y, point.pos.x - start.x)
	// 	point.dist = linalg.distance(point.pos, start)
	// }

	// slice.sort_by(points[:], proc(j, i: Point) -> bool {
	// 	if abs(i.angle - j.angle) < 0.0001 {
	// 		return i.dist < j.dist
	// 	}
	// 	return i.angle < j.angle
	// })

	// clear(&self.points)
	// for point in points {
	// 	append(&self.points, point.pos)
	// }
}

// text_view_draw_highlight_shape :: proc(self: ^Text_View) {
// 	selection := text_view_get_ordered_selection(self)

// 	Rounded_Box :: struct {
// 		using box: Box,
// 		radii:     [4]f32,
// 	}

// 	Box_Group :: [dynamic]Rounded_Box

// 	boxes := make([dynamic]Rounded_Box, allocator = context.temp_allocator)
// 	groups := make([dynamic]Box_Group, allocator = context.temp_allocator)
// 	shapes := make([dynamic]kn.Shape, allocator = context.temp_allocator)

// 	populate_group :: proc(group: ^Box_Group, box: Box, boxes: ^[dynamic]Rounded_Box) -> bool {
// 		found: bool
// 		for other, i in boxes {
// 			if box.lo == other.box.lo && box.hi == other.box.hi {
// 				continue
// 			}
// 			if box_overlaps_other(box, other) {
// 				append(group, other)
// 				ordered_remove(boxes, i)
// 				found = true
// 				populate_group(group, other, boxes)
// 			}
// 		}
// 		return found
// 	}

// 	for node in self.nodes {
// 		box := node_get_text_selection_box(node)
// 		if box.lo.x >= box.hi.x {
// 			continue
// 		}
// 		append(&boxes, Rounded_Box{box, 3})
// 	}

// 	group := make([dynamic]Rounded_Box, allocator = context.temp_allocator)
// 	for len(boxes) {
// 		if !populate_group(&group, box, &boxes) {
// 			ordered_remove(&boxes, i)
// 			append(&group, box)
// 		}
// 		append(&groups, group)
// 		group := make([dynamic]Rounded_Box, allocator = context.temp_allocator)
// 	}

// 	for group in groups {
// 		clear(&shapes)
// 		for box in group {
// 			if len(shapes) > 0 {
// 				last_box := &shapes[len(shapes) - 1]
// 				if box.lo.x <= last_box.cv1.x + 1 &&
// 				   box.lo.y == last_box.cv0.y &&
// 				   box.hi.y == last_box.cv1.y {
// 					last_box.cv1.x = box.hi.x
// 					continue
// 				}
// 			}
// 			append(&shapes, kn.make_box(box, 3))
// 		}
// 		if len(shapes) == 0 {
// 			return
// 		}
// 		kn.add_linked_shapes(..shapes[:], paint = Color{0, 255, 100, 100})
// 	}
// }

//
// Agent for managing text selection in text views
//
Text_Agent :: struct {
	// Storage
	stack:             [dynamic]^Text_View,
	dict:              map[Id]^Text_View,
	array:             [dynamic]Text_View,

	// State
	last_click_time:   time.Time,
	last_mouse_button: Mouse_Button,
	click_index:       int,
	hovered_view:      ^Text_View,
	hovered_id:        Id,
	active_view:       ^Text_View,
	active_id:         Id,
	focused_view:      ^Text_View,
}

text_agent_begin_view :: proc(self: ^Text_Agent, desc: Text_View_Descriptor) -> Maybe(^Text_View) {
	view, ok := self.dict[desc.id]
	if !ok {
		append(&self.array, Text_View{desc = desc})
		view = &self.array[len(self.array) - 1]
		self.dict[desc.id] = view
	}
	append(&self.stack, view)

	view.desc = desc
	view.byte_length = 0
	view.dead = false

	if view.selection != view.last_selection {
		text_view_update_viewport(view)
	}

	if view.selection != view.last_selection {
		view.last_selection = view.selection
		text_view_update_hightlight_shape(view)
	}

	if view.container_node != nil {
		view.container_node.text_view = view
	}

	if !view.editing {
		strings.builder_reset(&view.builder)
	}

	clear(&view.glyphs)
	clear(&view.nodes)

	return view
}

text_agent_end_view :: proc(self: ^Text_Agent) {
	if view, ok := text_agent_current_view(self); ok {
		view.selection[0] = clamp(view.selection[0], 0, len(view.glyphs))
		view.selection[1] = clamp(view.selection[1], 0, len(view.glyphs))
		text_view_update_cursor_box(view)
		pop(&self.stack)
	}
}

text_agent_on_mouse_down :: proc(self: ^Text_Agent, button: Mouse_Button) {
	self.active_view = self.hovered_view
	self.active_id = self.hovered_id

	if self.active_view != nil {
		if time.since(self.last_click_time) < time.Millisecond * 400 {
			self.click_index = (self.click_index + 1) % 3
		} else {
			self.click_index = 0
		}

		self.last_click_time = time.now()

		text_view_on_mouse_down(self.active_view, self.click_index)
	}

	self.focused_view = self.hovered_view
}

text_agent_on_mouse_up :: proc(self: ^Text_Agent) {
	// self.active_id = 0
	// self.active_view = nil
}

text_agent_on_new_frame :: proc(self: ^Text_Agent) {
	for &view, i in self.array {
		if view.dead {
			delete(view.glyphs)
			delete(view.nodes)
			delete_key(&self.dict, view.id)
			unordered_remove(&self.array, i)
		} else {
			view.dead = true
			view.active = self.active_view == &view
		}
	}

	assert(len(self.stack) == 0)
}

text_agent_current_view :: proc(self: ^Text_Agent) -> (view: ^Text_View, ok: bool) {
	if len(self.stack) == 0 {
		return
	}
	return self.stack[len(self.stack) - 1], true
}

text_agent_on_mouse_move :: proc(self: ^Text_Agent, mouse_position: [2]f32) {
	if self.hovered_view != nil {
		text_view_on_mouse_move(self.hovered_view, mouse_position)
	}
}

text_agent_when_mouse_down :: proc(self: ^Text_Agent) {
	if self.active_view != nil {
		text_view_when_mouse_down(self.active_view, self.click_index)
	}
}

text_agent_get_selection_string :: proc(self: ^Text_Agent) -> string {
	if self.focused_view != nil {
		return text_view_get_selection_string(self.focused_view)
	}
	return ""
}
