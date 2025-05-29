package opal

import "core:fmt"
import "core:io"
import "core:math"
import "core:math/linalg"
import "core:strings"
import "core:time"
import "core:unicode"

//
// An abstraction that manages multiple nodes with text content.
//
// Any interactive node with text will be included in only the top text on the stack at the time.
//
Text_View :: struct {
	// Identifier
	id:          Id,

	// Text length in bytes
	byte_length: int,

	// Hovered glyph index
	hover_index: int,

	// Selection in glyph indices
	selection:   [2]int,

	// Anchor for word selection
	anchor:      int,

	// Interactive nodes with text
	nodes:       [dynamic]^Node,

	// All glyphs, interactive or not
	glyphs:      [dynamic]Glyph,

	// Text
	data:        [dynamic]u8,

	// Active
	active:      bool,

	// Kill flag
	dead:        bool,
}

text_view_on_mouse_move :: proc(self: ^Text_View, mouse_position: [2]f32) {
	self.hover_index = -1

	min_dist: [2]f32 = INFINITY
	closest_y: f32

	for node in self.nodes {
		dist_y := abs((node.text_origin.y + node.text_size.y / 2) - mouse_position.y)
		if dist_y < min_dist.y {
			min_dist.y = dist_y
			closest_y = node.text_origin.y
		}
	}

	for node, node_index in self.nodes {
		if node.text_origin.y != closest_y {
			continue
		}

		for glyph, glyph_index in node.glyphs {
			dist := abs((node.text_origin.x + glyph.offset.x) - mouse_position.x)

			if dist < min_dist.x {
				min_dist.x = dist
				self.hover_index = glyph_index + node.text_glyph_index
			}
		}

		if len(node.glyphs) > 0 {
			dist := abs((node.text_origin.x + node.text_size.x) - mouse_position.x)

			if dist < min_dist.x {
				min_dist.x = dist
				self.hover_index = len(node.glyphs) + node.text_glyph_index
			}
		}
	}
}

text_view_on_mouse_down :: proc(self: ^Text_View, index: int) {
	self.selection = self.hover_index
	self.anchor = self.hover_index
}

text_view_when_mouse_down :: proc(self: ^Text_View, index: int) {

	is_separator :: proc(r: rune) -> bool {
		return !unicode.is_alpha(r) && !unicode.is_number(r)
	}

	data := string(self.data[:])

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

text_agent_begin_view :: proc(self: ^Text_Agent, id: Id) -> Maybe(^Text_View) {
	text, ok := self.dict[id]
	if !ok {
		append(&self.array, Text_View{id = id})
		text = &self.array[len(self.array) - 1]
		self.dict[id] = text
	}
	append(&self.stack, text)

	text.byte_length = 0
	text.dead = false
	clear(&text.data)
	clear(&text.glyphs)
	clear(&text.nodes)

	return text
}

text_agent_end_view :: proc(self: ^Text_Agent) {
	pop(&self.stack)
}

text_agent_on_mouse_down :: proc(self: ^Text_Agent, button: Mouse_Button) {
	self.active_view = self.hovered_view
	self.active_id = self.hovered_id

	if self.active_view != nil {
		self.active_view.active = true

		if time.since(self.last_click_time) < time.Millisecond * 400 {
			self.click_index = (self.click_index + 1) % 3
		} else {
			self.click_index = 0
		}

		self.last_click_time = time.now()

		text_view_on_mouse_down(self.active_view, self.click_index)
	} else if self.focused_view != nil {
		self.focused_view.active = false
	}

	self.focused_view = self.hovered_view
}

text_agent_on_mouse_up :: proc(self: ^Text_Agent) {
	self.active_id = 0
	self.active_view = nil
}

text_agent_on_new_frame :: proc(self: ^Text_Agent) {
	for &text, i in self.array {
		if text.dead {
			delete(text.glyphs)
			delete(text.nodes)
			delete_key(&self.dict, text.id)
			unordered_remove(&self.array, i)
		} else {
			text.dead = true
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

