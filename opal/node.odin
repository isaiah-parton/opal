package opal

import kn "../katana"
import tw "../tailwind_colors"
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
	stroke_type:      Stroke_Type,
	stroke:           Paint_Option,
	background:       Paint_Variant,
	foreground:       Paint_Option,
	font:             ^Font `fmt:"-"`,
	shadow_color:     Color,
	scale:            [2]f32,
	translate:        [2]f32,
	rotation:         f32,
	shadow_offset:    [2]f32,
	stroke_width:     f32,
	font_size:        f32,
	shadow_size:      f32,
	underline:        bool,
}

/*
Node_Empty :: struct {
	size: [2]f32,
}

Node_Text :: struct {
	data: string,
	size: f32,
	font: ^Font,
}

Node_Arc :: struct {
	fill:         Paint_Variant,
	start_angle:  f32,
	end_angle:    f32,
	inner_radius: f32,
	outer_radius: f32,
	square:       bool,
}

Node_Rectangle :: struct {
	fill:          Paint_Variant,
	stroke:        Paint_Variant,
	radii:         [4]f32,
	size:          [2]f32,
	shadow_color:  Color,
	shadow_offset: [2]f32,
	shadow_size:   f32,
	stroke_width:  f32,
	stroke_type:   Stroke_Type,
}

Node_Variant :: union #no_nil {
	Node_Empty,
	Node_Text,
	Node_Arc,
	Node_Rectangle,
}
*/

Sizing_Descriptor :: struct {
	// Exact initial size
	exact:        [2]f32,

	// Base size relative to parent
	relative:     [2]f32,

	// How much of the content space the node will grow to fit
	fit:          [2]f32,

	// How much of the parents space the node will grow to fill
	grow:         [2]f32,

	// The maximum fixed size the node is allowed to grow to
	max:          [2]f32,

	// Forced aspect ratio
	aspect_ratio: f32,
}

//
// The transient data belonging to a node for only the frame's duration.
// This is reset every frame when the node is invoked.
//
Node_Descriptor :: struct {
	using style:      Node_Style,

	// Sizing
	sizing:           Sizing_Descriptor,

	// Text
	text:             string,

	// Z index (higher values appear in front of lower ones), this value accumulates down the tree
	layer:            i32,

	// The node's final box will be loosely bound within this box, maintaining its size
	bounds:           Maybe(Box),

	//
	cursor:           Cursor,

	// Absolute placement
	exact_offset:     [2]f32,
	relative_offset:  [2]f32,
	align:            [2]f32,

	// Values for the node's children layout
	padding:          [4]f32,

	// How the content will be aligned if there is extra space
	content_align:    [2]f32,

	// Spacing added between children
	gap:              f32,

	// Absolute nodes aren't affected by their parent's layout'
	// they will instead be placed at their parent's position +
	// `exact_offset` + `relative_offset` * the parent's size -
	// `align` * the node's size
	absolute:         bool,

	//
	justify_between:  bool,

	// If this node will inherit the combined state of its children
	group:            bool,

	// If the node's children are arranged vertically
	vertical:         bool,

	// Wraps contents
	wrapped:          bool,

	// Prevents the node from being adopted and instead adds it as a new root.
	is_root:          bool,

	// If overflowing content is clipped
	clip_content:     bool,

	// If text content can be selected
	enable_selection: bool,

	// Show/hide scrollbars when content overflows
	show_scrollbars:  bool,

	// Causes the node to maintain a hovered and active state until the mouse is released
	sticky:           bool,

	// Must be true for the node to receive mouse and keyboard events
	interactive:      bool,

	// Called after the default drawing behavior
	on_draw:          proc(self: ^Node),

	// Data for use in callbacks, this data should live from the invocation of this node until the UI is ended.
	data:             rawptr,
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
	using descriptor:  Node_Descriptor,

	// Node tree references
	parent:            ^Node,
	children:          [dynamic]^Node `fmt:"-"`,

	// Layout tree references
	layout_parent:     ^Node,
	layout_children:   [dynamic]^Node `fmt:"-"`,

	// Each node holds a reference to its immediate view
	view:              ^View,

	// A simple kill switch that causes the node to be discarded
	dead:              bool,

	// The node's size has changed and a sizing pass will be triggered
	dirty:             bool,

	// Last frame on which this node was invoked
	// Currently, this is only used to check for ID collisions
	frame:             int,

	// Time of last mouse down event over this node
	last_click_time:   time.Time,

	// Unique identifier
	id:                Id `fmt:"x"`,

	// The node's local position within its parent; or screen position if its a root
	position:          [2]f32,

	// The accumulated size of the node on this frame. This value is unstable!
	size:              [2]f32,

	// Amount of content overflow
	// Computed at end of frame
	overflow:          [2]f32,

	// This is computed as the minimum space required to fit all children or the node's text content with padding
	content_size:      [2]f32,

	// The timestamp of the node's initialization in the context's arena
	// time_created:       time.Time,

	// Text stuff
	text_origin:       [2]f32,
	text_size:         [2]f32,
	text_view:         ^Text_View,
	text_byte_index:   int,
	text_glyph_index:  int,
	text_hash:         u32,
	glyphs:            []Glyph `fmt:"-"`,

	// View offset of contents
	scroll:            [2]f32,
	target_scroll:     [2]f32,

	// Universal state transition values for smooth animations
	transitions:       [3]f32,

	// The node's final placement in screen coordinates
	box:               Box,

	// If this is the node with the highest z-index that the mouse overlaps
	was_hovered:       bool,
	is_hovered:        bool,
	has_hovered_child: bool,

	// Active state (clicked)
	was_active:        bool,
	is_active:         bool,
	has_active_child:  bool,

	// Focused state: by default, a node is focused when clicked and loses focus when another node is clicked
	was_focused:       bool,
	is_focused:        bool,
	has_focused_child: bool,

	// Times the node was clicked
	click_count:       u8,

	// An arbitrary boolean state
	is_toggled:        bool,

	// Needs scissor
	has_clipped_child: bool,
	is_clipped:        bool,
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
	self.is_active = ctx.node_activation != nil && ctx.node_activation.?.which == self.id

	self.was_focused = self.is_focused
	self.is_focused = ctx.focused_id == self.id && ctx.window_is_focused

	if self.is_hovered || self.is_active {
		set_cursor(self.cursor)
	}
}

node_update_propagated_input :: proc(self: ^Node) {
	self.has_hovered_child = false
	self.has_active_child = false
	self.has_focused_child = false
}

node_receive_propagated_input :: proc(self: ^Node, child: ^Node) {
	self.has_hovered_child |= child.is_hovered | child.has_hovered_child
	self.has_active_child |= child.is_active | child.has_active_child
	self.has_focused_child |= child.is_focused | child.has_focused_child
	if self.group {
		self.is_hovered |= self.has_hovered_child
		self.is_active |= self.has_active_child
		self.is_focused |= self.has_focused_child
	}
}

node_propagate_input_recursive :: proc(self: ^Node, depth := 0) {
	if depth >= MAX_TREE_DEPTH {
		return
	}
	node_update_propagated_input(self)
	node_update_input(self)
	for node in self.children {
		node_propagate_input_recursive(node)
		node_receive_propagated_input(self, node)
	}
}

node_get_text_box :: proc(self: ^Node) -> Box {
	return {self.text_origin, self.text_origin + self.text_size}
}

node_get_text_selection_box :: proc(self: ^Node) -> Box {
	ordered_selection := text_view_get_ordered_selection(self.text_view)
	indices := [2]int {
		clamp(ordered_selection[0] - self.text_glyph_index, 0, len(self.glyphs)),
		clamp(ordered_selection[1] - self.text_glyph_index, 0, len(self.glyphs)),
	}
	return {
		node_get_glyph_position(self, indices[0]),
		node_get_glyph_position(self, indices[1]) + {0, self.font.line_height * self.font_size},
	}
}

node_update_scroll :: proc(self: ^Node) {
	// Update and clamp scroll
	self.target_scroll = linalg.clamp(self.target_scroll, 0, self.overflow)
	previous_scroll := self.scroll
	self.scroll = linalg.clamp(
		linalg.lerp(self.scroll, self.target_scroll, rate_per_second(10)),
		0,
		self.overflow,
	)
	if max(abs(self.scroll.x - previous_scroll.x), abs(self.scroll.y - previous_scroll.y)) > 0.01 {
		draw_frames(1)
	}
}

node_on_child_end :: proc(self: ^Node, child: ^Node) {
	if child.absolute {
		return
	}
	// Propagate dirty state
	self.dirty |= child.dirty
	// Propagate content size
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

aabb_intersects_segment_2d :: proc(
	aabb_min: [2]f32,
	aabb_max: [2]f32,
	p1: [2]f32,
	p2: [2]f32,
) -> bool {
	// Initialize t parameters for the segment
	t_min := f32(0.0)
	t_max := f32(1.0)

	d := p2 - p1
	epsilon :: f32(0.0001)

	// Loop through X (i=0) and Y (i=1)
	for i := 0; i < 2; i += 1 {
		// Get the relevant components for the current axis
		p1_i := p1[i]
		d_i := d[i]
		v_min_i := aabb_min[i]
		v_max_i := aabb_max[i]

		// --- Handle Parallel Case ---
		if abs(d_i) < epsilon {
			if (p1_i < v_min_i) || (p1_i > v_max_i) {
				return false // Parallel and outside the slab
			}
		} else {
			// --- General Case ---
			t_near := (v_min_i - p1_i) / d_i
			t_far := (v_max_i - p1_i) / d_i

			// Ensure t_near is always smaller than t_far
			if t_near > t_far {
				t_near, t_far = t_far, t_near
			}

			// Update the intersection interval
			// The latest entry point (t_min)
			if t_near > t_min {
				t_min = t_near
			}
			// The earliest exit point (t_max)
			if t_far < t_max {
				t_max = t_far
			}

			// Check if the intersection interval collapsed
			if t_min > t_max {
				return false
			}
		}
	}

	// The line segment intersects if the final interval [t_min, t_max] is valid
	// AND overlaps the segment range [0, 1].
	// Since we initialized t_min=0 and t_max=1, this check suffices:
	return true
}

node_receive_input :: proc(self: ^Node, layer: i32) -> (mouse_overlap: bool) {
	ctx := global_ctx
	// if ctx.mouse_position.x >= self.box.lo.x &&
	//    ctx.mouse_position.x <= self.box.hi.x &&
	//    ctx.mouse_position.y >= self.box.lo.y &&
	//    ctx.mouse_position.y <= self.box.hi.y {
	if aabb_intersects_segment_2d(
		self.box.lo,
		self.box.hi,
		ctx.last_mouse_position,
		ctx.mouse_position,
	) {
		when ODIN_DEBUG {
			inspector_register_node_under_mouse(&ctx.inspector, self)
		}
		mouse_overlap = true
		if self.interactive && !(ctx.hovered_node != nil && ctx.hovered_node.layer > layer) {
			ctx.hovered_node = self
			if node_is_scrollable(self) {
				ctx.scrollable_node = self
			}
		}
	}
	return
}

node_receive_input_recursive :: proc(self: ^Node, layer: i32 = 0) {
	layer := layer + self.layer
	mouse_overlap := node_receive_input(self, layer)

	if !mouse_overlap && self.clip_content {
		return
	}

	for node in self.children {
		node_receive_input_recursive(node, layer)
	}
}

node_solve_box :: proc(self: ^Node, offset: [2]f32) {
	// Nodes' cached sizes are used here because at this point they should represent the actual sizes
	if self.absolute {
		assert(self.layout_parent != nil)
		self.position = self.layout_parent.size * self.relative_offset + self.exact_offset
		self.position -= self.size * self.align
	} else if self.is_root {
		self.position = self.exact_offset + global_ctx.screen_size * self.relative_offset
	}

	self.box.lo = offset + self.position
	if bounds, ok := self.bounds.?; ok {
		self.box.lo = linalg.clamp(self.box.lo, bounds.lo, bounds.hi - self.size)
	}
	self.box.hi = self.box.lo + self.size

	// Re-implement this
	if global_ctx.snap_to_pixels {
		box_snap(&self.box)
	}
}

node_get_is_size_affected_by_parent :: proc(self: ^Node) -> bool {
	return !self.absolute
}

node_solve_absolute_size :: proc(self: ^Node) {
	assert(self.layout_parent != nil)
	self.size += self.layout_parent.size * self.sizing.relative
}

node_solve_box_recursive :: proc(
	self: ^Node,
	dirty: bool,
	offset: [2]f32 = {},
	clip_box: Box = {0, INFINITY},
) {
	node_solve_box(self, offset)

	clip_box := clip_box

	if self.parent != nil {
		clip := box_get_rounded_clip(self.box, clip_box, self.parent.radius.x)
		self.parent.has_clipped_child |= clip != .None
		self.is_clipped = clip == .Full
	}

	when ODIN_DEBUG {
		global_ctx.performance_info.drawn_nodes += int(!self.is_clipped)
	}

	clip_box = box_clamped(clip_box, self.box)

	self.has_clipped_child = false
	for node in self.children {
		node_solve_box_recursive(
			node,
			dirty,
			self.box.lo - self.scroll * f32(i32(!node.absolute)),
			clip_box,
		)
	}
}

//
// Layout section
//

//
// Solve one continuous extent of children along an axis
//
node_solve_child_placement_in_range :: proc(self: ^Node, from, to: int, span, line_offset: f32) {
	i := int(self.vertical)
	j := 1 - i

	// Slice the children D:
	children := self.layout_children[from:to]

	// Array of growing nodes along the layout axis
	growables := make(
		[dynamic]^Node,
		len = 0,
		cap = len(children),
		allocator = context.temp_allocator,
	)

	// The fixed content length along layout axis
	length: f32

	// Populate the array and accumulate node extent
	for node in children {

		// Grow child across axis (span)
		if node.sizing.grow[j] > 0 {
			node.size[j] = min(span * node.sizing.grow[j], node.sizing.max[j])
			node.overflow[j] = linalg.max(node.content_size[j] - node.size[j], 0)
		}

		// Check for aspect ratio to enforce
		if node.sizing.aspect_ratio != 0 {
			target_aspect := node.sizing.aspect_ratio
			// Invert ratios if layout is horizontal
			if i == 0 {
				target_aspect = 1 / target_aspect
			}
			// Clamp max growable size based on aspect ratio
			node.sizing.max[i] = min(node.sizing.max[i], node.size[j] / target_aspect)
		}

		// Increase total size along axis (length)
		length += node.size[i]

		// Add to growables array if grow factor is non-zero
		if node.sizing.grow[i] > 0 {
			append(&growables, node)
		}
	}

	// Add gaps as content length
	length += self.gap * f32(len(children) - 1)

	// Grow children to their maximum sizes and get the leftover space
	length_left := node_grow_children(
		self,
		&growables,
		// Compute the amount of space left for growth
		self.size[i] - self.padding[i] - self.padding[i + 2] - length,
	)

	// Equal spacing between children
	spacing := (length_left / f32(len(children) - 1)) if self.justify_between else self.gap

	// Starting position for children along layout axis
	offset: f32 = self.padding[i] + length_left * self.content_align[i]

	// Apply aspect ratios
	for node in children {
		if node.sizing.aspect_ratio != 0 {
			target_aspect := node.sizing.aspect_ratio
			// Invert ratios if layout is horizontal
			if i == 0 {
				target_aspect = 1 / target_aspect
			}
			// Clamp max growable size based on aspect ratio
			node.size[1 - i] = node.size[i] * target_aspect
		}
	}

	// Next, position children along layout axis + grow and position them across it
	for node in children {
		// Place child along axis
		node.position[i] = offset

		// Place child across axis
		node.position[j] =
			self.padding[j] +
			line_offset +
			(span + self.overflow[j] - node.size[j]) * self.content_align[j]

		offset += node.size[i] + spacing
	}
}

node_enforce_aspect_ratio :: proc(node: ^Node) {
	current_aspect := node.size.x / node.size.y

	if node.sizing.aspect_ratio > current_aspect {
		node.size.y = node.size.x / node.sizing.aspect_ratio
	} else {
		node.size.x = node.size.y * node.sizing.aspect_ratio
	}
}

//
// Solve wrapped or normal layout
//
node_solve_child_placement :: proc(self: ^Node) -> (needs_resolve: bool) {
	i := int(self.vertical)
	j := 1 - i

	offset: f32
	max_offset := self.size[i] - self.padding[i] - self.padding[i + 2]

	// The maximum span (size across layout axis) of all child nodes
	line_span: f32

	// Check if wrapping is enabled
	if self.wrapped {

		// Calculate content size
		line_start: int
		content_size: [2]f32

		for child, child_index in self.layout_children {
			// Detect when the content size would excede the available space
			if offset + child.size[i] > max_offset {

				// Grow the nodes that do fit
				node_solve_child_placement_in_range(
					self,
					line_start,
					child_index,
					line_span,
					content_size[j],
				)

				// Check if there's only one child
				if offset == 0 {
					// If so, include it's size
					content_size[i] = max(content_size[i], offset + child.size[i])
				} else {
					// Otherwise, reset offset
					content_size[i] = max(content_size[i], offset)
					offset = 0
				}

				// Grow the parent node to fit the wrapped content
				// Increase span by the line span + gap
				content_size[j] += line_span + self.gap

				line_start = child_index
				line_span = 0
			}
			line_span = max(line_span, child.size[j])
			offset += child.size[i] + self.gap
		}

		if line_span == 0 {
			line_span = node_get_span(self)
		}

		// Solve sizes
		node_solve_child_placement_in_range(
			self,
			line_start,
			len(self.layout_children),
			line_span,
			content_size[j],
		)

		// Add padding to content size
		content_size += self.padding.xy + self.padding.zw

		// Fit final run of nodes
		content_size[j] += line_span

		// TODO: Remove or keep this
		// WORKAROUND: Prevents nodes that wrap on different axis from 'fighting for space' when they share a parent. This lets only nodes with a different axis from their parent grow when wrapped.
		// if self.parent != nil && self.parent.vertical == self.vertical {
		// 	line_offset = min(
		// 		line_offset,
		// 		self.parent.size[j] - self.parent.padding[j] - self.parent.padding[j + 2],
		// 	)
		// }

		// Check if the node should grow
		if self.wrapped && self.content_size != content_size {
			self.content_size = content_size
			node_fit_to_content(self)

			// Trigger resolve of entire tree
			needs_resolve = true
		}
	} else {
		// Solve sizes normally
		node_solve_child_placement_in_range(
			self,
			0,
			len(self.layout_children),
			self.size[j] - self.padding[j] - self.padding[j + 2],
			0,
		)
	}

	return
}

//
// Expand all growable children and return the remaining space
//
node_grow_children :: proc(self: ^Node, array: ^[dynamic]^Node, length: f32) -> f32 {
	length := length

	i := int(self.vertical)

	// As long as there is remaining space and children to grow
	for length > 0 && len(array) > 0 {

		// Get the smallest size along the layout axis, nodes of this size will be grown first
		smallest := array[0].size[i]

		// Until they reach this size
		second_smallest := f32(math.F32_MAX)
		size_to_add := length

		// Figure out the smallest and second smallest sizes
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

		// TODO: Remove the loop?
		for node, node_index in array {
			if node.size[i] == smallest {
				// Compute the size to add to this child
				size_to_add := min(
					size_to_add,
					min(node.sizing.max[i], node.sizing.grow[i] * self.size[i]) - node.size[i],
				)

				// Remove the node when it's done growing
				if size_to_add <= 0 {
					unordered_remove(array, node_index)
					continue
				}

				// Grow the node
				node.size[i] += size_to_add

				// Check for aspect ratio to enforce
				// We need to enforce aspect ratio anywhere growth or fitting happens
				// TODO: Maybe move this functionality to a node_resize proc?
				// if node.sizing.aspect_ratio != 0 {
				// 	target_aspect := node.sizing.aspect_ratio
				// 	// Invert ratios if layout is horizontal
				// 	if i == 0 {
				// 		target_aspect = 1 / target_aspect
				// 	}
				// 	// Clamp max growable size based on aspect ratio
				// 	node.size[1 - i] = node.size[i] * target_aspect
				// }

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
// Walks down the tree, calculating node sizes, wrapping contents and then
// propagating size changes back up the tree for an optional second pass
//
node_solve_child_placement_and_wrap_recursive :: proc(
	self: ^Node,
	depth := 0,
) -> (
	needs_resolve: bool,
) {
	if depth >= MAX_TREE_DEPTH {
		return
	}

	needs_resolve = node_solve_child_placement(self)

	if self.wrapped {
		for child in self.layout_children {
			needs_resolve |= node_solve_child_placement_and_wrap_recursive(child, depth + 1)
		}
		if needs_resolve {
			node_solve_child_placement(self)
		}
	} else {
		i := int(self.vertical)
		j := 1 - i

		content_size: [2]f32

		for child in self.layout_children {
			needs_resolve |= node_solve_child_placement_and_wrap_recursive(child, depth + 1)

			content_size[i] += child.size[i]
			content_size[j] = max(content_size[j], child.size[j])
		}

		content_size += self.padding.xy + self.padding.zw

		content_size[i] += self.gap * f32(len(self.layout_children) - 1)

		if self.content_size != content_size {
			self.content_size = content_size
			node_fit_to_content(self)
		}
	}

	self.overflow = linalg.max(self.content_size - self.size, 0)

	return
}

//
// Second pass
//
node_solve_child_placement_recursive :: proc(self: ^Node, depth := 0) {
	if depth >= MAX_TREE_DEPTH {
		return
	}

	if self.wrapped {
		return
	}

	// self.overflow = linalg.max(self.content_size - self.size, 0)
	node_solve_child_placement_in_range(self, 0, len(self.layout_children), node_get_span(self), 0)

	for node in self.layout_children {
		node_solve_child_placement_recursive(node, depth + 1)
	}

	return
}

//
// Procedures for transforming nodes
//
node_get_span :: proc(self: ^Node) -> f32 {
	if self.vertical {
		return self.size.x - self.padding.x - self.padding.z
	} else {
		return self.size.y - self.padding.y - self.padding.w
	}
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
					&source,
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

node_draw_recursive :: proc(self: ^Node, layer: i32 = 0, depth := 0) {
	assert(depth < MAX_TREE_DEPTH)

	if self.is_clipped {
		return
	}

	enable_scissor :=
		self.clip_content &&
		(self.has_clipped_child ||
				max(self.overflow.x, self.overflow.y) > 0.1 ||
				max(abs(self.scroll.x), abs(self.scroll.y)) > 0.1)

	layer := layer + self.layer

	is_transformed :=
		self.style.scale != 1 || self.style.translate != 0 || self.style.rotation != 0

	kn.set_draw_order(int(layer))

	// Perform transformations
	if is_transformed {
		transform_origin := self.box.lo + self.size * self.style.transform_origin
		kn.push_matrix()
		kn.translate(transform_origin)
		kn.rotate(self.style.rotation)
		kn.scale(self.style.scale)
		kn.translate(-transform_origin + self.style.translate)
	}

	// Shadow
	if self.shadow_color != {} {
		kn.add_box_shadow(
			{self.box.lo + self.shadow_offset, self.box.hi + self.shadow_offset},
			self.radius[0],
			self.shadow_size,
			self.shadow_color,
		)
	}

	// Apply clipping
	if enable_scissor {
		when ODIN_DEBUG {
			if global_ctx.inspector.show_clipped_nodes {
				kn.add_box_lines(self.box, 1, self.style.radius, kn.RED)
				kn.add_box(self.box, self.style.radius, kn.fade(kn.RED, 0.3))
			}
		}
		kn.push_scissor(kn.make_box(self.box, self.style.radius))
	}

	// Draw self
	if self.background != {} {
		kn.add_box(
			box_shrink(self.box, self.style.stroke_width - 0.5) if self.style.stroke_type == .Inner else self.box,
			self.style.radius - self.style.stroke_width,
			paint = node_convert_paint_variant(self, self.background),
		)
	}

	// Custom draw method
	if self.on_draw != nil {
		self.on_draw(self)
	}

	// Text highlight
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

		// Draw debug helpers
		when ODIN_DEBUG {
			if global_ctx.inspector.show_text_widgets {
				rgba := linalg.vector4_hsl_to_rgb(
					math.mod(f32(self.id) * 0.00001, 1.0),
					0.9,
					0.45,
					0.25,
				)
				kn.add_box(self.box, 0, kn.color_from_rgba(rgba))
			}
		}

		// Draw selection
		if self.enable_selection && self.text_view.active {
			// TODO: implement custom selection color
			paint := kn.paint_index_from_option(
				fade(global_ctx.theme.color.selection_background, 0.5),
			)

			selection := [2]int {
				clamp(self.text_view.selection[0] - self.text_glyph_index, 0, len(self.glyphs)),
				clamp(self.text_view.selection[1] - self.text_glyph_index, 0, len(self.glyphs)),
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

		// Draw individual glyphs
		for &glyph in self.glyphs {
			kn.add_glyph(glyph, self.font_size, self.text_origin + glyph.offset, paint)
		}

		// Draw underline
		if self.style.underline {
			y_offset := self.font.ascend * self.font_size + 2
			kn.add_box(
				{
					self.text_origin + {0, y_offset},
					self.text_origin + {self.text_size.x, y_offset + 2},
				},
				0,
				paint,
			)
		}

		// Draw cursor
		cursor_index := self.text_view.selection[1] - self.text_byte_index

		if self.enable_selection && self.text_view.active && self.text_view.show_cursor {
			if cursor_index >= 0 && cursor_index <= len(self.glyphs) {
				kn.add_box(box_floored(self.text_view.cursor_box), paint = get_text_cursor_color())
			}
		}
	}

	// Draw children
	for node in self.children {
		node_draw_recursive(node, layer, depth + 1)
	}

	if enable_scissor {
		kn.pop_scissor()
	}

	// Outline
	if self.style.stroke != nil && self.style.stroke_width > 0 {
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
}

node_get_glyph_position :: proc(self: ^Node, index: int, loc := #caller_location) -> [2]f32 {
	assert(index >= 0, loc = loc)
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

node_fit_to_content :: proc(self: ^Node) {
	if self.sizing.fit == {} {
		return
	}

	self.size = linalg.max(self.content_size * self.sizing.fit, self.size)

	// Enforce non-zero aspect ratios
	if self.sizing.aspect_ratio != 0 {
		node_enforce_aspect_ratio(self)
	}
}

//
// Get an existing node by its id or create a new one
//
acquire_node :: proc(id: Id) -> Maybe(^Node) {
	ctx := global_ctx
	if node, ok := ctx.node_by_id[id]; ok {
		return node
	} else {
		for &slot, slot_index in ctx.nodes {
			if slot == nil {
				ctx.nodes[slot_index] = Node {
					id = id,
					// time_created = time.now(),
				}
				node = &ctx.nodes[slot_index].?
				ctx.node_by_id[id] = node
				draw_frames(1)
				return node
			}
		}
	}
	return nil
}

begin_node :: proc(desc: ^Node_Descriptor, loc := #caller_location) -> (self: Node_Result) {
	ctx := global_ctx
	self = acquire_node(hash_loc(loc))

	if self, ok := self.?; ok {
		if desc != nil {
			if desc.sizing != self.sizing {
				self.dirty = true
			}
			self.descriptor = desc^
		}

		if self.absolute || ctx.current_node == nil {
			self.position = self.exact_offset
		}

		if !self.is_root {
			self.parent = ctx.current_node
			assert(self != self.parent)

			self.layout_parent = self.parent

			if self.layout_parent != nil {
				if !self.absolute {
					append(&self.layout_parent.layout_children, self)
				}

				self.dirty |= self.layout_parent.dirty
			}
		}

		// Nodes with no layout parent get added to the layout roots, otherwise they still need a parent to be placed relative to
		if self.absolute || self.layout_parent == nil {
			append(&ctx.layout_roots, self)
		}

		// Root
		if self.parent == nil {
			append(&ctx.roots, self)
			begin_text_view({id = self.id})
		} else {
			append(&self.parent.children, self)
			self.layer = desc.layer + self.parent.layer
		}

		// Clear arrays and reserve memory
		reserve(&self.children, 16)
		reserve(&self.layout_children, 16)
		clear(&self.children)
		clear(&self.layout_children)

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

		self.text_view = get_current_text() or_else panic("No text context initialized!")

		// Create text layout
		if reader, ok := reader.?; ok {

			self.text_size = 0
			self.text_glyph_index =
				len(self.text_view.glyphs) if self.enable_selection else len(ctx.glyphs)
			self.text_byte_index = self.text_view.byte_length

			if self.enable_selection {
				append(&self.text_view.nodes, self)
				if !self.text_view.editing {
					strings.write_string(&self.text_view.builder, self.text)
				}
			}

			glyphs := &self.text_view.glyphs if self.enable_selection else &ctx.glyphs

			hash: u32 = FNV1A32_OFFSET_BASIS

			for {
				char, length, err := io.read_rune(reader)

				if err == .EOF {
					break
				}

				hash = hash ~ (u32(char) * FNV1A32_PRIME)

				switch char {
				case '\t':
					append(
						glyphs,
						Glyph {
							node = self,
							index = self.text_view.byte_length,
							offset = {self.text_size.x, 0},
						},
					)
					self.text_size.x += self.font.space_advance * self.font_size * 2
				case '\n':
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
				case '\r':
				case:
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
				}

				self.text_size.x += self.gap

				if self.enable_selection {
					self.text_view.byte_length += length
				}
			}

			if hash != self.text_hash {
				draw_frames(1)
				self.text_hash = hash
			}

			self.text_size.x -= self.gap
			self.text_size.y = self.font.line_height * self.font_size

			self.glyphs = glyphs[self.text_glyph_index:]

			self.content_size = linalg.max(self.content_size, self.text_size)
		}

		push_node(self)
	}

	return
}

end_node :: proc() {
	ctx := global_ctx
	self := ctx.current_node

	if self == nil {
		return
	}

	i := int(self.vertical)

	//
	// Determine known size
	//
	if !self.wrapped {
		self.content_size[i] += self.gap * f32(max(len(self.children) - 1, 0))
	}

	self.content_size += self.padding.xy + self.padding.zw

	self.size = self.sizing.exact
	node_fit_to_content(self)

	//
	// Determine dirty state from size changes in known metrics
	//

	if self.dirty {
		draw_frames(1)
	}

	//
	// Handle scrolling
	//

	// Update scroll
	node_update_scroll(self)

	// Add scrollbars
	if self.show_scrollbars && self.overflow != {} {
		SCROLLBAR_SIZE :: 4
		SCROLLBAR_PADDING :: 2

		inner_box := box_shrink(self.box, 1)

		push_id(self.id)

		scrollbar_style := Node_Style {
			background = ctx.theme.color.selection_background,
			foreground = ctx.theme.color.selection_foreground,
			radius     = SCROLLBAR_SIZE / 2,
		}

		corner_space: f32

		if self.overflow.x > 0 && self.overflow.y > 0 {
			corner_space = SCROLLBAR_SIZE + SCROLLBAR_PADDING
		}

		if self.overflow.y > 0 {
			node := add_node(
				&{
					absolute = true,
					data = self,
					relative_offset = {1, 0},
					exact_offset = [2]f32{-SCROLLBAR_SIZE - SCROLLBAR_PADDING, SCROLLBAR_PADDING},
					sizing = {
						relative = {0, 1},
						exact = {SCROLLBAR_SIZE, SCROLLBAR_PADDING * -2 - corner_space},
						max = INFINITY,
					},
					interactive = true,
					sticky = true,
					style = scrollbar_style,
					on_draw = scrollbar_on_draw,
					vertical = true,
				},
			).?
			added_size := SCROLLBAR_SIZE * node.transitions[1]
			node.size.x += added_size
			node.exact_offset.x -= added_size
			node.radius = node.sizing.exact.x / 2
		}

		if self.overflow.x > 0 {
			node := add_node(
				&{
					absolute = true,
					data = self,
					relative_offset = {0, 1},
					exact_offset = {SCROLLBAR_PADDING, -SCROLLBAR_SIZE - SCROLLBAR_PADDING},
					sizing = {
						relative = {1, 0},
						exact = {-SCROLLBAR_PADDING * 2 - corner_space, SCROLLBAR_SIZE},
						max = INFINITY,
					},
					interactive = true,
					sticky = true,
					style = scrollbar_style,
					on_draw = scrollbar_on_draw,
				},
			).?
			added_size := SCROLLBAR_SIZE * 2 * node.transitions[1]
			node.size.y += added_size
			node.exact_offset.y -= added_size
			node.radius = node.size.y / 2
		}

		pop_id()
	}

	pop_node()
	if self.parent == nil {
		end_text_view()
	} else {
		node_on_child_end(self.parent, self)
	}
}

add_node :: proc(descriptor: ^Node_Descriptor, loc := #caller_location) -> Node_Result {
	self := begin_node(descriptor, loc)
	if self != nil {
		end_node()
	}
	return self
}

