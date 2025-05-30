package opal

import kn "../katana"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:sys/windows"
import "core:time"
import "core:unicode"
import tw "tailwind_colors"

//
// The visual description of a node, used for the default drawing procedure
// This is abstracted out by gut feeling ✊😔
//
Node_Style :: struct {
	// Corner radius
	radius:           [4]f32,

	// The origin of transformation (0, 0) = top left, (1, 1) = bottom right
	transform_origin: [2]f32,

	// Transformation applied to self and children
	scale:            [2]f32,
	translate:        [2]f32,
	rotation:         f32,
	stroke_type:      Stroke_Type,
	stroke:           Paint_Option,
	background:       Paint_Variant,
	foreground:       Paint_Option,
	font:             ^Font `fmt:"-"`,
	shadow_color:     Color,
	stroke_width:     f32,
	font_size:        f32,
	shadow_size:      f32,
}

//
// The transient data belonging to a node for only the frame's duration. This is reset every frame when the node is invoked.  Many of these values change as the UI tree is built.
//
Node_Descriptor :: struct {
	using style:        Node_Style,

	// Text
	text:               string,

	// Z index (higher values appear in front of lower ones), this value stacks down the tree
	z_index:            u32,

	// The node's final box will be loosely bound within this box, maintaining its size
	bounds:             Maybe(Box),

	//
	cursor:             Cursor,

	// Absolute nodes aren't affected by layout, they just get positioned and sized relative to their parent after its layout is known and then treated as roots
	absolute:           bool,

	//
	exact_offset:       [2]f32,
	exact_size:         [2]f32,
	relative_offset:    [2]f32,
	relative_size:      [2]f32,

	// The node's actual size, this is subject to change until the end of the frame. The initial value is effectively the node's minimum size
	min_size:           [2]f32,

	// The maximum size the node is allowed to grow to
	max_size:           [2]f32,

	// If the node will be grown to fill available space
	grow:               [2]bool,

	// If the node will grow to acommodate its contents
	fit:                [2]f32,

	// Values for the node's children layout
	padding:            [4]f32,

	// How the content will be aligned if there is extra space
	content_align:      [2]f32,

	// Spacing added between children
	gap:                f32,

	//
	justify_between:    bool,

	// If this node will inherit the combined state of its children
	inherit_state:      bool,

	// If the node's children are arranged vertically
	vertical:           bool,

	// Wraps contents
	wrapped:            bool,

	// Prevents the node from being adopted and instead adds it as a new root.
	is_root:            bool,

	// If overflowing content is clipped
	clip_content:       bool,

	// If text content can be selected
	enable_selection:   bool,

	// Disallows inspection in the debug inspector
	disable_inspection: bool,

	// Show/hide scrollbars when content overflows
	show_scrollbars:    bool,

	// Forces equal width and height when fitting to content size
	square_fit:         bool,

	//
	interactive:        bool,

	// An optional node that will behave as if it were this node's parent, when it doesn't in fact have one. Input state will be transfered to the owner.
	owner:              ^Node `fmt:"-"`,

	// Called after the default drawing behavior
	on_draw:            proc(self: ^Node),

	// Data for use in callbacks, this data should live from the invocation of this node until the UI is ended.
	data:               rawptr,
}

Glyph :: struct {
	using glyph: kn.Font_Glyph,
	offset:      [2]f32,
	index:       int,
	node:        ^Node,
}

//
// Generic UI nodes, everything is a made out of these
//
Node :: struct {
	using descriptor:        Node_Descriptor,

	// Node tree references
	parent:                  ^Node,
	children:                [dynamic]^Node `fmt:"-"`,

	// Layout tree references
	layout_parent:           ^Node,
	layout_children:         [dynamic]^Node `fmt:"-"`,

	// A simple kill switch that causes the node to be discarded
	dead:                    bool,

	// The node's size has changed and a sizing pass will be triggered
	dirty:                   bool,

	// Last frame on which this node was invoked
	frame:                   int,

	// Unique identifier
	id:                      Id `fmt:"x"`,

	// The node's local position within its parent; or screen position if its a root
	position:                [2]f32,

	//
	size:                    [2]f32,

	// The last size known at invocation
	last_size:               [2]f32,

	// Cached size to reuse when no sizing pass occurs
	cached_size:             [2]f32,

	// The content size minus the last calculated size
	overflow:                [2]f32,

	// This is computed as the minimum space required to fit all children or the node's text content with padding
	content_size:            [2]f32,

	// The `box` field represents the final position and size of the node and is only valid after `end()` has been called
	box:                     Box,

	// If this is the node with the highest z-index that the mouse overlaps
	was_hovered:             bool,
	is_hovered:              bool,
	has_hovered_child:       bool,

	// Active state (clicked)
	was_active:              bool,
	is_active:               bool,
	has_active_child:        bool,

	// Focused state: by default, a node is focused when clicked and loses focus when another node is clicked
	was_focused:             bool,
	is_focused:              bool,
	has_focused_child:       bool,
	// TODO: WHYYYY?!?!
	will_have_focused_child: bool,

	// Times the node was clicked
	click_count:             u8,

	// Time of last mouse down event over this node
	last_click_time:         time.Time,

	// Interaction
	is_toggled:              bool,

	// The timestamp of the node's initialization in the context's arena
	time_created:            time.Time,

	// Text stuff
	text_origin:             [2]f32,
	text_size:               [2]f32,
	text_view:               ^Text_View,
	text_byte_index:         int,
	text_glyph_index:        int,
	glyphs:                  []Glyph `fmt:"-"`,

	// View offset of contents
	scroll:                  [2]f32,
	target_scroll:           [2]f32,

	// Needs scissor
	has_clipped_child:       bool,
	is_clipped:              bool,

	// Universal state transition values for smooth animations
	transitions:             [3]f32,
}

push_node :: proc(node: ^Node) {
	ctx := global_ctx
	append(&ctx.node_stack, node)
	ctx.current_node = node
}

pop_node :: proc() {
	ctx := global_ctx
	pop(&ctx.node_stack)
	if len(ctx.node_stack) == 0 {
		ctx.current_node = nil
		return
	}
	ctx.current_node = ctx.node_stack[len(ctx.node_stack) - 1]
}

node_destroy :: proc(self: ^Node) {
	delete(self.children)
}

node_update_input :: proc(self: ^Node) {
	ctx := global_ctx

	self.was_hovered = self.is_hovered
	self.is_hovered = ctx.hovered_id == self.id

	self.was_active = self.is_active
	self.is_active = ctx.active_id == self.id

	self.was_focused = self.is_focused
	self.is_focused = ctx.focused_id == self.id && ctx.window_is_focused

	if self.is_hovered {
		set_cursor(self.cursor)
	}
}

node_update_propagated_input :: proc(self: ^Node) {
	self.has_hovered_child = false
	self.has_active_child = false

	self.has_focused_child = self.will_have_focused_child
	self.will_have_focused_child = false
}

node_receive_propagated_input :: proc(self: ^Node, child: ^Node) {
	self.has_hovered_child |= child.is_hovered | child.has_hovered_child
	self.has_active_child |= child.is_active | child.has_active_child
	self.has_focused_child |= child.is_focused | child.has_focused_child
	if self.inherit_state {
		self.is_hovered |= self.has_hovered_child
		self.is_active |= self.has_active_child
		self.is_focused |= self.has_focused_child
	}
}

node_propagate_input_recursively :: proc(self: ^Node, depth := 0) {
	assert(depth < MAX_TREE_DEPTH)
	node_update_propagated_input(self)
	node_update_input(self)
	for node in self.children {
		node_propagate_input_recursively(node)
		node_receive_propagated_input(self, node)
	}
	if self.owner != nil {
		node_receive_propagated_input(self.owner, self)
		self.owner.will_have_focused_child = self.has_focused_child | self.is_focused
	}
}

node_on_new_frame :: proc(self: ^Node) {
	ctx := global_ctx

	// Clear arrays and reserve memory
	reserve(&self.children, 16)
	clear(&self.children)

	if self.scale == {} {
		self.scale = 1
	}

	// Keep alive this frame
	self.dead = false

	// Reset some state
	self.content_size = 0

	// Initialize string reader for text construction
	string_reader: strings.Reader
	reader: Maybe(io.Reader)
	if len(self.text) > 0 {
		reader = strings.to_reader(&string_reader, self.text)
	}

	// Assign a default font for safety
	if self.style.font == nil {
		self.style.font = &kn.DEFAULT_FONT
		assert(self.style.font != nil)
	}

	// Create text layout
	if reader, ok := reader.?; ok {
		self.text_view = get_current_text() or_else panic("No text context initialized!")

		self.text_size = 0
		self.text_glyph_index =
			len(self.text_view.glyphs) if self.enable_selection else len(ctx.glyphs)
		self.text_byte_index = self.text_view.byte_length

		if self.enable_selection {
			append(&self.text_view.nodes, self)
			strings.write_string(&self.text_view.builder, self.text)
		}

		glyphs := &self.text_view.glyphs if self.enable_selection else &ctx.glyphs

		for {
			char, length, err := io.read_rune(reader)

			if err == .EOF {
				break
			}

			if char == '\t' {
				append(
					glyphs,
					Glyph {
						node = self,
						index = self.text_view.byte_length,
						offset = {self.text_size.x, 0},
					},
				)
				self.text_size.x += self.font.space_advance * self.font_size * 2
			} else if char == '\n' {
				append(
					glyphs,
					Glyph {
						node = self,
						index = self.text_view.byte_length,
						offset = {self.text_size.x, 0},
						glyph = {advance = self.font.space_advance},
					},
				)
				self.text_size.x += self.font.space_advance * self.font_size
			} else if glyph, ok := kn.get_font_glyph(self.font, char); ok {
				append(
					glyphs,
					Glyph {
						node = self,
						index = self.text_view.byte_length,
						glyph = glyph,
						offset = {self.text_size.x, 0},
					},
				)
				self.text_size.x += glyph.advance * self.font_size
			} else {
				for char in fmt.tprintf("<0x%x>", char) {
					if glyph, ok := kn.get_font_glyph(self.font, char); ok {
						append(
							glyphs,
							Glyph {
								node = self,
								index = self.text_view.byte_length,
								glyph = glyph,
								offset = {self.text_size.x, 0},
							},
						)
						self.text_size.x += glyph.advance * self.font_size
					}
				}
			}

			self.text_size.x += self.gap

			if self.enable_selection {
				self.text_view.byte_length += length
			}
		}

		self.text_size.x -= self.gap
		self.text_size.y = self.font.line_height * self.font_size

		self.glyphs = glyphs[self.text_glyph_index:]

		self.content_size = linalg.max(self.content_size, self.text_size)
	}

	// Root
	if self.parent == nil {
		append(&ctx.roots, self)
		//
		return
	}

	// Child logic
	append(&self.parent.children, self)
}

node_on_child_end :: proc(self: ^Node, child: ^Node) {
	self.dirty |= child.dirty
	// Propagate content size up the tree in reverse breadth-first
	if self.wrapped {
		self.content_size = linalg.max(self.content_size, child.size)
	} else {
		if self.vertical {
			self.content_size.y += child.size.y
			self.content_size.x = max(self.content_size.x, child.size.x)
		} else {
			self.content_size.x += child.size.x
			self.content_size.y = max(self.content_size.y, child.size.y)
		}
	}
}

node_receive_input :: proc(self: ^Node, z_index: u32) -> (mouse_overlap: bool) {
	ctx := global_ctx
	if ctx.mouse_position.x >= self.box.lo.x &&
	   ctx.mouse_position.x <= self.box.hi.x &&
	   ctx.mouse_position.y >= self.box.lo.y &&
	   ctx.mouse_position.y <= self.box.hi.y {
		mouse_overlap = true
		if self.interactive && !(ctx.hovered_node != nil && ctx.hovered_node.z_index > z_index) {
			ctx.hovered_node = self
			if node_is_scrollable(self) {
				ctx.scrollable_node = self
			}
		}
	}
	return
}

node_receive_input_recursive :: proc(self: ^Node, z_index: u32 = 0) {
	z_index := z_index + self.z_index
	if node_receive_input(self, z_index) {
		for node in self.children {
			node_receive_input_recursive(node, z_index)
		}
	}
}

node_solve_box :: proc(self: ^Node, offset: [2]f32) {
	self.box.lo = offset + self.position
	if bounds, ok := self.bounds.?; ok {
		self.box.lo = linalg.clamp(self.box.lo, bounds.lo, bounds.hi - self.size)
	}
	self.box.hi = self.box.lo + self.size
	// if global_ctx.snap_to_pixels {
	// 	box_snap(&self.box)
	// }
}

node_solve_box_recursively :: proc(
	self: ^Node,
	dirty: bool,
	offset: [2]f32 = {},
	clip_box: Box = {0, INFINITY},
) {
	if !dirty {
		self.size = self.cached_size
	}
	self.cached_size = self.size

	node_solve_box(self, offset)

	clip_box := clip_box

	if self.parent != nil {
		clip := box_get_rounded_clip(
			self.box,
			clip_box,
			max(
				self.parent.radius.x,
				max(self.parent.radius.y, max(self.parent.radius.z, self.parent.radius.w)),
			),
		)
		self.parent.has_clipped_child |= clip != .None
		self.is_clipped = clip == .Full
		when ODIN_DEBUG {
			global_ctx.drawn_nodes += int(!self.is_clipped)
		}
	}

	clip_box = box_clamped(clip_box, self.box)

	self.has_clipped_child = false
	for node in self.children {
		node_solve_box_recursively(node, dirty, self.box.lo - self.scroll, clip_box)
	}
}

node_solve_sizes_in_range :: proc(self: ^Node, from, to: int, span, line_offset: f32) {
	i := int(self.vertical)
	j := 1 - i

	children := self.children[from:to]

	growables := make(
		[dynamic]^Node,
		len = 0,
		cap = len(children),
		allocator = context.temp_allocator,
	)

	length: f32
	for node in children {
		length += node.size[i]
		if node.grow[i] {
			append(&growables, node)
		}
	}

	length += self.gap * f32(len(children) - 1)

	length_left := node_grow_children(
		self,
		&growables,
		self.size[i] - self.padding[i] - self.padding[i + 2] - length,
	)

	spacing := (length_left / f32(len(children) - 1)) if self.justify_between else self.gap

	offset: f32 = self.padding[i]

	for node in children {
		node.position[i] = offset + (length_left + self.overflow[i]) * self.content_align[i]

		if node.grow[j] {
			node.size[j] = span
		}

		node.position[j] =
			self.padding[j] +
			line_offset +
			(span + self.overflow[j] - node.size[j]) * self.content_align[j]

		offset += node.size[i] + spacing
	}
}

node_solve_sizes :: proc(self: ^Node) -> (needs_resolve: bool) {
	i := int(self.vertical)
	j := 1 - i

	offset: f32
	max_offset := self.size[i] - self.padding[i] - self.padding[i + 2]
	line_span: f32
	line_start: int

	content_size: [2]f32

	for child, child_index in self.children {
		if self.wrapped && offset + child.size[i] > max_offset {
			node_solve_sizes_in_range(self, line_start, child_index, line_span, content_size[j])
			line_start = child_index

			content_size[i] = max(content_size[i], offset)
			offset = 0
			content_size[j] += line_span + self.gap
			line_span = 0
		}
		line_span = max(line_span, child.size[j])
		offset += child.size[i] + self.gap
	}

	if !self.wrapped {
		line_span = self.size[j] - self.padding[j] - self.padding[j + 2]
	}

	node_solve_sizes_in_range(self, line_start, len(self.children), line_span, content_size[j])

	content_size[j] += line_span + self.padding[j] + self.padding[j + 2]

	// WORKAROUND: Prevents nodes that wrap on different axis from 'fighting for space' when they share a parent. This lets only nodes with a different axis from their parent grow when wrapped.
	// if self.parent != nil && self.parent.vertical == self.vertical {
	// 	line_offset = min(
	// 		line_offset,
	// 		self.parent.size[j] - self.parent.padding[j] - self.parent.padding[j + 2],
	// 	)
	// }

	if self.wrapped && self.content_size != content_size {
		self.content_size = content_size
		self.size = linalg.max(self.size, self.content_size * self.fit)
		needs_resolve = true
	}

	return
}

//
// Expand all growable children and return the remaining space
//
node_grow_children :: proc(self: ^Node, array: ^[dynamic]^Node, length: f32) -> f32 {
	length := length

	i := int(self.vertical)

	for length > 0 && len(array) > 0 {
		// Get the smallest size along the layout axis, nodes of this size will be grown first
		smallest := array[0].size[i]

		// Until they reach this size
		second_smallest := f32(math.F32_MAX)
		size_to_add := length

		for node in array {
			if node.size[i] < smallest {
				second_smallest = smallest
				smallest = node.size[i]
			}

			if node.size[i] > smallest {
				second_smallest = min(second_smallest, node.size[i])
			}
		}

		// Compute the smallest size to add
		size_to_add = min(second_smallest - smallest, length / f32(len(array)))

		// Add that amount to every eligable child
		for node, node_index in array {
			if node.size[i] == smallest {
				size_to_add := min(size_to_add, node.max_size[i] - node.size[i])

				// Remove the node when it's done growing
				if size_to_add <= 0 {
					unordered_remove(array, node_index)
					continue
				}

				// Grow the node
				node.size[i] += size_to_add

				// Add content size (this is important)
				self.content_size[i] += size_to_add

				// Decrease remaining space
				length -= size_to_add
			}
		}
	}

	return length
}

//
// Walks down the tree, calculating node sizes, wrapping contents and then propagating size changes back up the tree for an optional second pass
//
node_solve_sizes_and_wrap_recursive :: proc(self: ^Node, depth := 0) -> (needs_resolve: bool) {
	assert(depth < MAX_TREE_DEPTH)

	needs_resolve = node_solve_sizes(self)

	if self.wrapped {
		for child in self.children {
			needs_resolve |= node_solve_sizes_and_wrap_recursive(child, depth + 1)
		}
		if needs_resolve {
			node_solve_sizes(self)
		}
	} else {
		i := int(self.vertical)
		j := 1 - i

		content_size: [2]f32

		for child in self.children {
			needs_resolve |= node_solve_sizes_and_wrap_recursive(child, depth + 1)

			content_size[i] += child.size[i]
			content_size[j] = max(content_size[j], child.size[j])
		}

		content_size += self.padding.xy + self.padding.zw

		content_size[i] += self.gap * f32(len(self.children) - 1)

		if self.content_size != content_size {
			self.content_size = content_size
			self.size = linalg.max(self.size, self.content_size * self.fit)
			self.overflow = linalg.max(self.content_size - self.size, 0)
		}
	}

	return
}

//
// Second pass
//
node_solve_sizes_recursive :: proc(self: ^Node, depth := 0) {
	assert(depth < MAX_TREE_DEPTH)

	if self.wrapped {
		return
	}

	self.overflow = linalg.max(self.content_size - self.size, 0)
	node_solve_sizes_in_range(self, 0, len(self.children), node_get_content_span(self), 0)

	for node in self.children {
		node_solve_sizes_recursive(node, depth + 1)
	}

	return
}

node_get_content_span :: proc(self: ^Node) -> f32 {
	if self.vertical {
		return self.content_size.x - self.padding.x - self.padding.z
	} else {
		return self.content_size.y - self.padding.y - self.padding.w
	}
}

node_is_scrollable :: proc(self: ^Node) -> bool {
	return self.overflow != {}
}

node_convert_paint_variant :: proc(self: ^Node, variant: Paint_Variant) -> kn.Paint_Index {
	switch v in self.style.background {
	case kn.Color:
		return kn.paint_index_from_option(v)
	case Image_Paint:
		size := box_size(self.box)
		if source, ok := use_image(v.index); ok {
			return kn.add_paint(
				kn.make_atlas_sample(
					source,
					{self.box.lo + v.offset * size, self.box.lo + v.size * size},
					kn.WHITE,
				),
			)
		}
	case Radial_Gradient:
		return kn.add_paint(
			kn.make_radial_gradient(
				self.box.lo + v.center * self.size,
				v.radius * max(self.size.x, self.size.y),
				v.inner,
				v.outer,
			),
		)
	case Linear_Gradient:
		return kn.add_paint(
			kn.make_linear_gradient(
				self.box.lo + v.points[0] * self.size,
				self.box.lo + v.points[1] * self.size,
				v.colors[0],
				v.colors[1],
			),
		)
	}
	return 0
}

node_draw_recursive :: proc(self: ^Node, z_index: u32 = 0, depth := 0) {
	assert(depth < MAX_TREE_DEPTH)

	if self.is_clipped {
		return
	}

	enable_scissor :=
		self.clip_content &&
		(self.has_clipped_child ||
				max(self.overflow.x, self.overflow.y) > 0.1 ||
				max(abs(self.scroll.x), abs(self.scroll.y)) > 0.1)

	// Compute text selection state if enabled
	// if self.enable_selection {
	// 	cursor_box := text_get_cursor_box(&self.text_layout, text_origin)

	// 	// Make sure to clip the cursor
	// 	padded_box := node_get_padded_box(self)
	// 	left := max(0, padded_box.lo.x - cursor_box.lo.x)
	// 	top := max(0, padded_box.lo.y - cursor_box.lo.y)
	// 	right := max(0, cursor_box.hi.x - padded_box.hi.x)
	// 	bottom := max(0, cursor_box.hi.y - padded_box.hi.y)
	// 	enable_scissor |= max(left, right) > 0
	// 	enable_scissor |= max(top, bottom) > 0

	// 	// Scroll to bring cursor into view
	// 	if self.is_focused && self.editor.selection != self.last_selection {
	// 		self.target_scroll.x += right - left
	// 		self.target_scroll.y += bottom - top
	// 	}
	// }
	//

	z_index := z_index + self.z_index

	// Is transformation necessary?
	is_transformed :=
		self.style.scale != 1 || self.style.translate != 0 || self.style.rotation != 0

	kn.set_draw_order(int(z_index))

	// Perform transformations
	if is_transformed {
		transform_origin := self.box.lo + self.size * self.style.transform_origin
		kn.push_matrix()
		kn.translate(transform_origin)
		kn.rotate(self.style.rotation)
		kn.scale(self.style.scale)
		kn.translate(-transform_origin + self.style.translate)
	}

	if self.shadow_color != {} {
		kn.add_box_shadow(self.box, self.radius[0], self.shadow_size, self.shadow_color)
	}

	// Apply clipping
	if enable_scissor {
		kn.push_scissor(kn.make_box(self.box, self.style.radius))
	}

	// Draw self
	if self.background != {} {
		kn.add_box(
			self.box,
			self.style.radius,
			paint = node_convert_paint_variant(self, self.background),
		)
	}
	if self.style.foreground != nil && len(self.glyphs) > 0 {
		self.text_origin =
			linalg.lerp(
				self.box.lo + self.padding.xy,
				self.box.hi - self.padding.zw,
				self.content_align,
			) -
			self.text_size * self.content_align -
			self.scroll

		line_height := self.font.line_height * self.font_size

		if self.enable_selection && self.text_view.active {
			paint := kn.paint_index_from_option(fade(tw.INDIGO_700, 1))
			selection := [2]int {
				clamp(self.text_view.selection[0] - self.text_byte_index, 0, len(self.glyphs)),
				clamp(self.text_view.selection[1] - self.text_byte_index, 0, len(self.glyphs)),
			}
			ordered_selection := selection
			if ordered_selection[0] != ordered_selection[1] {
				if ordered_selection[0] > ordered_selection[1] {
					ordered_selection = ordered_selection.yx
				}
				kn.add_box(
					{
						node_get_glyph_position(self, ordered_selection[0]),
						node_get_glyph_position(self, ordered_selection[1]) + {0, line_height},
					},
					paint = paint,
				)
			}
		}

		paint := kn.paint_index_from_option(self.foreground)

		for &glyph in self.glyphs {
			kn.add_glyph(glyph, self.font_size, self.text_origin + glyph.offset, paint)
		}

		cursor_index := self.text_view.selection[1] - self.text_byte_index

		if self.enable_selection && self.text_view.active && self.text_view.show_cursor {
			if cursor_index >= 0 && cursor_index <= len(self.glyphs) {
				top_left := node_get_glyph_position(self, cursor_index)
				kn.add_box(
					{{top_left.x, top_left.y}, {top_left.x + 2, top_left.y + line_height}},
					paint = global_ctx.colors[.Selection_Background],
				)
			}
		}
	}

	if self.on_draw != nil {
		self.on_draw(self)
	}

	// Draw children
	for node in self.children {
		node_draw_recursive(node, z_index, depth + 1)
	}

	if enable_scissor {
		kn.pop_scissor()
	}

	if self.style.stroke != nil {
		kn.add_box_lines(
			self.box,
			self.style.stroke_width,
			self.style.radius,
			paint = self.style.stroke,
			outline = kn.Shape_Outline(
				int(self.style.stroke_type) + int(kn.Shape_Outline.Inner_Stroke),
			),
		)
	}

	if is_transformed {
		kn.pop_matrix()
	}

	// Draw debug lines
	if ODIN_DEBUG {
		ctx := global_ctx
		if ctx.inspector.inspected_id == self.id {
			too_smol: bool
			if self.parent != nil {
				if box_width(self.box) == 0 {
					too_smol = true
					kn.add_box(
						{
							{self.parent.box.lo.x + self.parent.padding.x, self.box.lo.y},
							{self.parent.box.hi.x - self.parent.padding.z, self.box.hi.y},
						},
						paint = kn.fade(kn.GREEN_YELLOW, 0.5),
					)
				}
				if box_height(self.box) == 0 {
					too_smol = true
					kn.add_box(
						{
							{self.box.lo.x, self.parent.box.lo.y + self.parent.padding.y},
							{self.box.hi.x, self.parent.box.hi.y - self.parent.padding.w},
						},
						paint = kn.fade(kn.GREEN_YELLOW, 0.5),
					)
				}
			}
			if !too_smol {
				// box := Box{self.box.lo - self.scroll, {}}
				// box.hi = box.lo + linalg.max(self.content_size, self.size)
				// box.hi = box.lo + self.size
				box := self.box
				padding_paint := kn.paint_index_from_option(kn.fade(kn.SKY_BLUE, 0.5))
				if self.padding.x > 0 {
					kn.add_box(
						box_clamped(box_cut_left(&box, self.padding.x), self.box),
						paint = padding_paint,
					)
				}
				if self.padding.y > 0 {
					kn.add_box(
						box_clamped(box_cut_top(&box, self.padding.y), self.box),
						paint = padding_paint,
					)
				}
				if self.padding.z > 0 {
					kn.add_box(
						box_clamped(box_cut_right(&box, self.padding.z), self.box),
						paint = padding_paint,
					)
				}
				if self.padding.w > 0 {
					kn.add_box(
						box_clamped(box_cut_bottom(&box, self.padding.w), self.box),
						paint = padding_paint,
					)
				}
				kn.add_box(box_clamped(box, self.box), paint = kn.fade(kn.BLUE_VIOLET, 0.5))
			}
		}
	}
}

node_get_glyph_position :: proc(self: ^Node, index: int) -> [2]f32 {
	if index == 0 {
		return self.text_origin
	}
	if index == len(self.glyphs) {
		return self.text_origin + {self.text_size.x, 0}
	}
	return self.text_origin + self.glyphs[index].offset
}

node_get_padded_box :: proc(self: ^Node) -> Box {
	return Box{self.box.lo + self.padding.xy, self.box.hi - self.padding.zw}
}
