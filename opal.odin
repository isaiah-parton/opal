package opal

//
// TODO:
// 	[x] Figure out how to let a node modify its own size
// 		- Probably through callbacks
//
//

import kn "../katana"
import "../katana/sdl3glue"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:time"
import "lucide"
import "tw"
import "vendor:sdl3"

// Generic unique identifiers
Id :: u32

Box :: kn.Box

Vector2 :: [2]f32

//
// **Padding**
//
// `{left, top, right, bottom}`
//
Padding :: [4]f32

Node_Config :: struct {
	p:               [4]f32,
	text:            string,
	pos:             [2]f32,
	size:            [2]f32,
	max_size:        [2]f32,
	rsize:           [2]f32,
	bg:              kn.Paint_Option,
	stroke:          kn.Paint_Option,
	fg:              kn.Paint_Option,
	font:            ^kn.Font,
	on_draw:         proc(_: ^Node),
	on_animate:      proc(_: ^Node),
	px:              f32,
	py:              f32,
	pl:              f32,
	pt:              f32,
	pr:              f32,
	pb:              f32,
	gap:             f32,
	w:               f32,
	h:               f32,
	max_w:           f32,
	max_h:           f32,
	self_align_x:    f32,
	self_align_y:    f32,
	content_align_x: f32,
	content_align_y: f32,
	stroke_width:    f32,
	radius:          f32,
	font_size:       f32,
	fit:             bool,
	fit_x:           bool,
	fit_y:           bool,
	grow:            bool,
	grow_x:          bool,
	grow_y:          bool,
	vertical:        bool,
	abs:             bool,
}

node_configure :: proc(self: ^Node, config: Node_Config) {
	self.is_absolute = config.abs
	self.padding = {
		max(config.p.x, config.px, config.pl),
		max(config.p.y, config.px, config.pt),
		max(config.p.z, config.py, config.pr),
		max(config.p.w, config.py, config.pb),
	}
	self.spacing = config.gap
	self.fit = {config.fit | config.fit_x, config.fit | config.fit_y}
	self.grow = {config.grow | config.grow_x, config.grow | config.grow_y}
	self.size = {max(config.size.x, config.w), max(config.size.y, config.h)}
	self.max_size = {max(config.max_size.x, config.max_w), max(config.max_size.y, config.max_h)}
	self.content_align = {config.content_align_x, config.content_align_y}
	self.align = {config.self_align_x, config.self_align_y}
	self.position = config.pos
	self.vertical = config.vertical
	self.style.radius = config.radius
	self.style.stroke_width = config.stroke_width
	self.style.stroke_paint = config.stroke
	self.style.background_paint = config.bg
	self.style.foreground_paint = config.fg
	self.style.font = config.font
	self.style.font_size = config.font_size
	self.text = config.text
	self.on_draw = config.on_draw
	self.on_animate = config.on_animate
	self.relative_size = config.rsize
}

node_config_clone_of_parent :: proc(config: Node_Config) -> Node_Config {
	config := config
	config.abs = true
	config.rsize = 1
	return config
}

Node_Info :: struct {
	style:         Node_Style,
	// The node's local position within its parent; or screen position if its a root
	position:      [2]f32,

	// The maximum size the node is allowed to grow to
	max_size:      [2]f32,

	// The node's actual size, this is subject to change until `end()` is called
	// The initial value is effectively the node's minimum size
	size:          [2]f32,

	// If the node will be grown to fill available space
	grow:          [2]bool,

	// If the node will grow to acommodate its kids
	fit:           [2]bool,

	// How the node is aligned on its origin if it is a root node
	align:         [2]f32,

	// Values for the node's children layout
	content_align: [2]f32,
	content_size:  [2]f32,
	padding:       [4]f32,
	spacing:       f32,
	vertical:      bool,

	// Z index (higher values appear in front of lower ones)
	z_index:       u32,

	// Draw logic override
	on_animate:    proc(self: ^Node),
	on_draw:       proc(self: ^Node),

	// User data
	user_data:     rawptr,
}

//
// The ultimate UI element abstraction
//
// Opal UIs are built entirely out of these guys, they are stylable layouts, rectangles, text, icons and whatever else you make them through their user callbacks.
//
Node :: struct {
	// Node tree references
	parent:             ^Node,
	kids:               [dynamic]^Node,

	//
	is_dead:            bool,

	// Unique identifier
	id:                 Id,

	// The `box` field represents the final position and size of the node and is only valid after `end()` has been called
	box:                Box,

	// The node's local position within its parent; or screen position if its a root
	position:           [2]f32,

	// Absolute nodes are translated from their parent's origin relative to its size before their fixed position is added
	relative_position:  [2]f32,

	// The maximum size the node is allowed to grow to
	max_size:           [2]f32,

	// This is for the node itself to add/subtract from its size on the next frame
	added_size:         [2]f32,

	// The node's actual size, this is subject to change until `end()` is called
	// The initial value is effectively the node's minimum size
	size:               [2]f32,

	// Added size relative to the parent
	relative_size:      [2]f32,

	// If the node will be grown to fill available space
	grow:               [2]bool,

	// If the node will grow to acommodate its kids
	fit:                [2]bool,

	// How the node is aligned on its origin if it is a root node
	align:              [2]f32,

	// Values for the node's children layout
	padding:            [4]f32,
	content_align:      [2]f32,
	content_size:       [2]f32,
	growable_kid_count: int,
	spacing:            f32,
	vertical:           bool,
	is_absolute:        bool,

	// Opal sacrifices one frame of responsiveness for faster frames. This value is a representation of the previous frame's input
	is_hovered:         bool,

	// True if any nodes below this one in the tree are hovered
	has_hovered_child:  bool,

	// Clicked
	is_active:          bool,
	has_active_child:   bool,
	clip_content:       bool,

	// Z index (higher values appear in front of lower ones)
	z_index:            u32,

	// Appearance
	text:               string,
	text_layout:        kn.Text,
	style:              Node_Style,
	transitions:        [3]f32,

	// Draw logic override
	on_animate:         proc(self: ^Node),
	on_draw:            proc(self: ^Node),

	// User data
	user_data:          rawptr,
}

//
// This is abstracted out by gut feeling ✊😔
//
Node_Style :: struct {
	radius:           [4]f32,
	transform_origin: [2]f32,
	scale:            [2]f32,
	translate:        [2]f32,
	stroke_join:      kn.Shape_Outline,
	stroke_paint:     kn.Paint_Option,
	background_paint: kn.Paint_Option,
	foreground_paint: kn.Paint_Option,
	font:             ^kn.Font,
	shadow_color:     kn.Color,
	rotation:         f32,
	stroke_width:     f32,
	font_size:        f32,
	shadow_size:      f32,
	transform_kids:   bool,
}

@(init)
_print_struct_memory_configuration :: proc() {
	fmt.println(size_of(Node), align_of(Node))
}

Cursor :: enum {
	Normal,
	Pointer,
}

On_Set_Cursor_Proc :: #type proc(cursor: Cursor) -> bool
On_Set_Clipboard_Proc :: #type proc(data: string)
On_Get_Clipboard_Proc :: #type proc() -> string

Mouse_Button :: enum {
	Left,
	Middle,
	Right,
}

Context :: struct {
	// Input state
	mouse_position:        Vector2,
	mouse_button_down:     [Mouse_Button]bool,
	mouse_button_was_down: [Mouse_Button]bool,
	hovered_node:          ^Node,
	focused_node:          ^Node,
	active_node:           ^Node,
	hovered_id:            Id,
	focused_id:            Id,
	active_id:             Id,
	on_set_cursor:         On_Set_Cursor_Proc,
	on_set_clipboard:      On_Set_Clipboard_Proc,
	on_get_clipboard:      On_Get_Clipboard_Proc,
	cursor:                Cursor,
	last_cursor:           Cursor,

	// Map of node ids
	nodes_by_id:           map[Id]^Node,

	// Contiguous storage of all nodes in the UI
	nodes:                 [dynamic]Node,

	// All nodes wihout a parent are stored here for layout solving
	// They are the root nodes of their layout trees
	roots:                 [dynamic]^Node,

	// The stack of nodes being declared
	stack:                 [dynamic]^Node,

	// The hash stack
	id_stack:              [dynamic]Id,

	// The top-most element of the stack
	current_node:          ^Node,

	// Profiling state
	frame_start_time:      time.Time,
	frame_duration:        time.Duration,

	// Debug state
	is_debugging:          bool,
}

@(private)
global_ctx: ^Context

//
// Unique ID hashing for retaining node states
//

// FNV1A64_OFFSET_BASIS :: 0xcbf29ce484222325
// FNV1A64_PRIME :: 0x00000100000001B3

// fnv64a :: proc(data: []byte, seed: u64) -> u64 {
// 	h: u64 = seed
// 	for b in data {
// 		h = (h ~ u64(b)) * FNV1A64_PRIME
// 	}
// 	return h
// }

FNV1A32_OFFSET_BASIS :: 0x811c9dc5
FNV1A32_PRIME :: 0x01000193

fnv32a :: proc(data: []byte, seed: u32) -> u32 {
	h: u32 = seed
	for b in data {
		h = (h ~ u32(b)) * FNV1A32_PRIME
	}
	return h
}

hash :: proc {
	hash_string,
	hash_rawptr,
	hash_uintptr,
	hash_bytes,
	hash_loc,
	hash_int,
}

hash_int :: #force_inline proc(num: int) -> Id {
	ctx := global_ctx
	hash := ctx.id_stack[len(ctx.id_stack) - 1]
	return hash ~ (Id(num) * FNV1A32_PRIME)
}

hash_string :: #force_inline proc(str: string) -> Id {
	return hash_bytes(transmute([]byte)str)
}

hash_rawptr :: #force_inline proc(data: rawptr, size: int) -> Id {
	return hash_bytes(([^]u8)(data)[:size])
}

hash_uintptr :: #force_inline proc(ptr: uintptr) -> Id {
	ptr := ptr
	return hash_bytes(([^]u8)(&ptr)[:size_of(ptr)])
}

hash_bytes :: proc(bytes: []byte) -> Id {
	ctx := global_ctx
	return fnv32a(bytes, ctx.id_stack[len(ctx.id_stack) - 1])
}

hash_loc :: proc(loc: runtime.Source_Code_Location) -> Id {
	hash := hash_bytes(transmute([]byte)loc.file_path)
	hash = hash ~ (Id(loc.line) * FNV1A32_PRIME)
	hash = hash ~ (Id(loc.column) * FNV1A32_PRIME)
	return hash
}

//
// Nodes' IDs are hashed from their call location normally. Opal provides an ID stack so you can push a loop index to the stack and ensure that all your list items have a unique ID.
//

push_id_int :: proc(num: int) {
	ctx := global_ctx
	append(&ctx.id_stack, hash_int(num))
}

push_id_string :: proc(str: string) {
	ctx := global_ctx
	append(&ctx.id_stack, hash_string(str))
}

push_id_other :: proc(id: Id) {
	ctx := global_ctx
	append(&ctx.id_stack, id)
}

push_id :: proc {
	push_id_int,
	push_id_string,
	push_id_other,
}

pop_id :: proc() {
	ctx := global_ctx
	pop(&ctx.id_stack)
}

//
// Context procs
//

context_init :: proc(ctx: ^Context) {
	assert(ctx != nil)
	reserve(&ctx.nodes, 2048)
	reserve(&ctx.roots, 64)
	reserve(&ctx.stack, 64)
	reserve(&ctx.id_stack, 64)
}

context_deinit :: proc(ctx: ^Context) {
	assert(ctx != nil)
}

context_set_clipboard :: proc(ctx: ^Context, data: string) {
	if ctx.on_set_clipboard == nil {
		return
	}
	ctx.on_set_clipboard(data)
}

set_clipboard :: proc(data: string) {
	context_set_clipboard(global_ctx, data)
}

rate_per_second :: proc(rate: f32) -> f32 {
	ctx := global_ctx
	return f32(time.duration_seconds(ctx.frame_duration)) * rate
}

//
// Global context proc wrappers
//

init :: proc() {
	global_ctx = new(Context)
	context_init(global_ctx)
}

deinit :: proc() {
	context_deinit(global_ctx)
}

//
// Call these from your event loop to handle input events
//

handle_mouse_motion :: proc(x, y: f32) {
	global_ctx.mouse_position = {x, y}
}

handle_text_input :: proc(text: cstring) {

}

handle_key_down :: proc() {

}

handle_mouse_down :: proc(button: Mouse_Button) {
	ctx := global_ctx
	ctx.mouse_button_down[button] = true
}

handle_mouse_up :: proc(button: Mouse_Button) {
	ctx := global_ctx
	ctx.mouse_button_down[button] = false
}

mouse_down :: proc(button: Mouse_Button) -> bool {
	ctx := global_ctx
	return ctx.mouse_button_down[button]
}

mouse_pressed :: proc(button: Mouse_Button) -> bool {
	ctx := global_ctx
	return ctx.mouse_button_down[button] && !ctx.mouse_button_was_down[button]
}

mouse_released :: proc(button: Mouse_Button) -> bool {
	ctx := global_ctx
	return !ctx.mouse_button_down[button] && ctx.mouse_button_was_down[button]
}

//
// Clear the UI construction state for a new frame
//
begin :: proc() {
	ctx := global_ctx
	if ctx.frame_start_time != {} {
		ctx.frame_duration = time.since(ctx.frame_start_time)
	}
	ctx.frame_start_time = time.now()

	clear(&ctx.id_stack)
	clear(&ctx.stack)
	clear(&ctx.roots)
	clear(&ctx.nodes)

	push_id(Id(FNV1A32_OFFSET_BASIS))
	ctx.current_node = nil
	ctx.hovered_node = nil
	ctx.focused_node = nil
	ctx.active_node = nil
}

//
// Ends UI declaration and constructs the final layout, node boxes are only valid after this is called
//
end :: proc() {
	ctx := global_ctx

	if ctx.on_set_cursor != nil && ctx.cursor != ctx.last_cursor {
		if ctx.on_set_cursor(ctx.cursor) {
			ctx.last_cursor = ctx.cursor
		}
	}
	ctx.cursor = .Normal

	for root in ctx.roots {
		root.box.lo = root.position - root.size * root.align
		root.box.hi = root.box.lo + root.size

		node_finish_layout_recursively(root)
		node_solve_box_recursively(root)

		kn.set_draw_order(int(root.z_index))
		node_draw_recursively(root)
	}

	for &node, node_index in ctx.nodes {
		if node.is_dead {
			delete_key(&ctx.nodes_by_id, node.id)
			unordered_remove(&ctx.nodes, node_index)
		} else {
			node.is_dead = true
		}
	}

	if ctx.is_debugging {
		if ctx.hovered_node != nil {
			kn.add_box_lines(ctx.hovered_node.box, 1, paint = kn.Blue)
		}
	}
	kn.set_draw_order(0)

	if ctx.hovered_node != nil {
		ctx.hovered_id = ctx.hovered_node.id
	} else {
		ctx.hovered_id = 0
	}
	if ctx.focused_node != nil {
		ctx.focused_id = ctx.focused_node.id
	} else {
		ctx.focused_id = 0
	}
	if ctx.active_node != nil {
		ctx.active_id = ctx.active_node.id
	} else if mouse_released(.Left) {
		ctx.active_id = 0
	}

	ctx.mouse_button_was_down = ctx.mouse_button_down
}

set_cursor :: proc(cursor: Cursor) {
	global_ctx.cursor = cursor
}

//
// Attempt to overwrite the currently hovered node respecting z-index
//
// The memory pointed to by `node` must live until the next frame
//
try_hover_node :: proc(node: ^Node) {
	ctx := global_ctx
	if ctx.hovered_node != nil && ctx.hovered_node.z_index > node.z_index {
		return
	}
	ctx.hovered_node = node
}

push_node :: proc(node: ^Node) {
	ctx := global_ctx
	append(&ctx.stack, node)
	ctx.current_node = ctx.stack[len(ctx.stack) - 1]
}

pop_node :: proc() {
	ctx := global_ctx
	pop(&ctx.stack)
	if len(ctx.stack) == 0 {
		ctx.current_node = nil
		return
	}
	ctx.current_node = ctx.stack[len(ctx.stack) - 1]
}

default_node_style :: proc() -> Node_Style {
	return {
		background_paint = kn.Black,
		foreground_paint = kn.White,
		stroke_paint = kn.DimGray,
		stroke_width = 1,
	}
}

text_node_style :: proc() -> Node_Style {
	return {stroke_width = 1}
}

node_init :: proc(self: ^Node) {
	self.kids = make([dynamic]^Node, 0, 16, allocator = context.temp_allocator)
}

node_on_new_frame :: proc(self: ^Node, config: Node_Config) {
	ctx := global_ctx

	self.style.scale = 1

	node_configure(self, config)

	self.is_dead = false
	self.content_size = 0

	self.is_hovered = ctx.hovered_id == self.id
	self.has_hovered_child = false

	self.is_active = ctx.active_id == self.id
	self.has_active_child = false

	if len(self.text) > 0 {
		font := kn.DEFAULT_FONT if self.style.font == nil else self.style.font^
		self.text_layout = kn.make_text(self.text, self.style.font_size, font)
		self.content_size = linalg.max(self.content_size, self.text_layout.size)
	}

	self.size += self.added_size

	if self.parent == nil {
		append(&ctx.roots, self)
		return
	}

	append(&self.parent.kids, self)

	if self.grow[int(self.parent.vertical)] {
		self.parent.growable_kid_count += 1
	}
}

//
// Get an existing node by its id or create a new one
//
get_or_create_node :: proc(id: Id) -> ^Node {
	ctx := global_ctx
	node, ok := ctx.nodes_by_id[id]
	if !ok {
		append(&ctx.nodes, Node{id = id})
		node = &ctx.nodes[len(ctx.nodes) - 1]
		ctx.nodes_by_id[id] = node
	}
	if node == nil {
		fmt.panicf(
			"get_or_create_node(%i) would return an invalid pointer! This is UNACCEPTABLEEE!!!",
			id,
		)
	}
	node.parent = ctx.current_node
	return node
}

begin_node :: proc(config: Node_Config, loc := #caller_location) -> (self: ^Node) {
	self = get_or_create_node(hash_loc(loc))
	node_init(self)
	node_on_new_frame(self, config)
	push_node(self)
	return
}

end_node :: proc() {
	ctx := global_ctx
	self := ctx.current_node
	if self == nil {
		return
	}
	i := int(self.vertical)
	self.content_size += self.padding.xy + self.padding.zw
	self.content_size[i] += self.spacing * f32(max(len(self.kids) - 1, 0))
	self.size = linalg.max(
		self.size,
		self.content_size * {f32(i32(self.fit.x)), f32(i32(self.fit.y))},
	)
	pop_node()
	if ctx.current_node != nil {
		node_on_child_end(ctx.current_node, self)
	}
}

do_node :: proc(config: Node_Config, loc := #caller_location) {
	begin_node(config, loc)
	end_node()
}

//
// Layout logic
//

node_on_child_end :: proc(self: ^Node, child: ^Node) {
	// Propagate content size up the tree in reverse breadth-first
	if self.vertical {
		self.content_size.y += child.size.y
		self.content_size.x = max(self.content_size.x, child.size.x)
	} else {
		self.content_size.x += child.size.x
		self.content_size.y = max(self.content_size.y, child.size.y)
	}
	self.has_hovered_child = self.has_hovered_child | child.is_hovered | child.has_hovered_child
	self.has_active_child = self.has_active_child | child.is_active | child.has_active_child
}

node_solve_box_recursively :: proc(self: ^Node) {
	for node in self.kids {
		node.box.lo = self.box.lo + node.position
		node.box.hi = node.box.lo + node.size
		node_solve_box_recursively(node)
	}
}

node_finish_layout_recursively :: proc(self: ^Node) {
	// Along axis
	i := int(self.vertical)
	// Across axis
	j := 1 - i

	remaining_space := self.size[i] - self.content_size[i]

	growables := make(
		[dynamic]^Node,
		0,
		self.growable_kid_count,
		allocator = context.temp_allocator,
	)

	for &node in self.kids {
		if !node.is_absolute && node.grow[i] {
			append(&growables, node)
		}
	}

	for remaining_space > 0 && len(growables) > 0 {
		// Get the smallest size along the layout axis, nodes of this size will be grown first
		smallest := growables[0].size[i]
		// Until they reach this size
		second_smallest := f32(math.F32_MAX)
		size_to_add := remaining_space
		for node in growables {
			if node.size[i] < smallest {
				second_smallest = smallest
				smallest = node.size[i]
			}
			if node.size[i] > smallest {
				second_smallest = min(second_smallest, node.size[i])
			}
		}

		size_to_add = min(second_smallest - smallest, remaining_space / f32(len(growables)))

		for node, node_index in growables {
			if node.size[i] == smallest {
				size_to_add := min(size_to_add, node.max_size[i] - node.size[i])
				if size_to_add <= 0 {
					unordered_remove(&growables, node_index)
					continue
				}
				node.size[i] += size_to_add
				remaining_space -= size_to_add
			}
		}
	}

	offset_along_axis: f32 = self.padding[i]
	for node in self.kids {
		if node.is_absolute {
			node.position += self.size * node.relative_position
			node.size += self.size * node.relative_size
		} else {
			available_span := self.size[j] - self.padding[j] - self.padding[j + 2]

			if node.grow[j] {
				node.size[j] = max(node.size[j], available_span)
			}

			node.position[j] =
				self.padding[j] + (available_span - node.size[j]) * self.content_align[j]
			node.position[i] = offset_along_axis + remaining_space * self.content_align[i]
			offset_along_axis += node.size[i] + self.spacing
		}
		node_finish_layout_recursively(node)
	}
}

node_receive_input :: proc(self: ^Node) {
	ctx := global_ctx
	if ctx.mouse_position.x >= self.box.lo.x &&
	   ctx.mouse_position.x <= self.box.hi.x &&
	   ctx.mouse_position.y >= self.box.lo.y &&
	   ctx.mouse_position.y <= self.box.hi.y {
		try_hover_node(self)
	}
	if self.is_hovered {
		if mouse_pressed(.Left) {
			ctx.active_node = self
		}
	}
}

node_draw_recursively :: proc(self: ^Node, depth := 0) {
	ctx := global_ctx
	node_receive_input(self)
	if self.on_animate != nil {
		self.on_animate(self)
	}

	is_transformed :=
		self.style.scale != 1 || self.style.translate != 0 || self.style.rotation != 0

	if is_transformed {
		transform_origin := self.box.lo + self.size * self.style.transform_origin
		kn.push_matrix()
		kn.translate(transform_origin)
		kn.rotate(self.style.rotation)
		kn.scale(self.style.scale)
		kn.translate(-transform_origin + self.style.translate)
	}

	if self.clip_content {
		kn.push_scissor(kn.make_box(self.box))
	}

	if self.on_draw != nil {
		self.on_draw(self)
	} else {
		node_draw_default(self)
	}

	if self.clip_content {
		kn.pop_scissor()
	}

	if is_transformed {
		kn.pop_matrix()
	}

	for node in self.kids {
		node_draw_recursively(node, depth + 1)
	}

	if ctx.is_debugging && self.has_hovered_child {
		kn.add_box_lines(self.box, 1, paint = kn.LightGreen)
	}
}

node_draw_default :: proc(self: ^Node) {
	if self.style.shadow_color != {} {
		kn.add_box_shadow(
			self.box,
			self.style.radius[0],
			self.style.shadow_size,
			self.style.shadow_color,
		)
	}
	if self.style.background_paint != nil {
		kn.add_box(self.box, self.style.radius, paint = self.style.background_paint)
	}
	if self.style.foreground_paint != nil && !kn.text_is_empty(&self.text_layout) {
		kn.add_text(
			self.text_layout,
			(self.box.lo + self.box.hi) / 2 - self.text_layout.size / 2,
			paint = self.style.foreground_paint,
		)
	}
	if self.style.stroke_paint != nil {
		kn.add_box_lines(
			self.box,
			self.style.stroke_width,
			self.style.radius,
			paint = self.style.stroke_paint,
		)
	}
}

//
// The demo UI
//

cursors: [sdl3.SystemCursor]^sdl3.Cursor

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	if !sdl3.Init({.VIDEO}) {
		panic("Could not initialize SDL3")
	}
	defer sdl3.Quit()

	window := sdl3.CreateWindow("OPAL", 800, 600, {.RESIZABLE})
	defer sdl3.DestroyWindow(window)

	platform := sdl3glue.make_platform_sdl3glue(window)
	defer kn.destroy_platform(&platform)

	kn.start_on_platform(platform)
	defer kn.shutdown()

	lucide.load()

	init()
	defer deinit()

	ctx := global_ctx

	// Create system cursors
	for cursor in sdl3.SystemCursor {
		cursors[cursor] = sdl3.CreateSystemCursor(cursor)
	}

	// Set cursor callback
	ctx.on_set_cursor = proc(cursor: Cursor) -> bool {
		switch cursor {
		case .Normal:
			return sdl3.SetCursor(cursors[.DEFAULT])
		case .Pointer:
			return sdl3.SetCursor(cursors[.POINTER])
		}
		return false
	}

	loop: for {
		sdl3.Delay(10)
		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break loop
			case .KEY_DOWN:
				if event.key.key == sdl3.K_F1 {
					ctx.is_debugging = !ctx.is_debugging
				}
			case .MOUSE_BUTTON_DOWN:
				handle_mouse_down(Mouse_Button(int(event.button.button) - 1))
			case .MOUSE_BUTTON_UP:
				handle_mouse_up(Mouse_Button(int(event.button.button) - 1))
			case .MOUSE_MOTION:
				handle_mouse_motion(event.motion.x, event.motion.y)
			case .WINDOW_PIXEL_SIZE_CHANGED:
				width, height: i32
				sdl3.GetWindowSize(window, &width, &height)
				kn.set_size(width, height)
			case .TEXT_INPUT:
				handle_text_input(event.text.text)
			}
		}

		do_frame()
	}
}

string_from_rune :: proc(char: rune, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator = allocator)
	strings.write_rune(&b, char)
	return strings.to_string(b)
}

do_button :: proc(label: union #no_nil {
		string,
		rune,
	}, font: ^kn.Font = nil, font_size: f32 = 14, loc := #caller_location) {
	do_node({
			p = 3,
			fit = true,
			text = label.(string) or_else string_from_rune(label.(rune)),
			font_size = font_size,
			fg = tw.SLATE_800,
			font = font,
			on_animate = proc(self: ^Node) {
				self.style.background_paint = kn.mix(
					self.transitions[0],
					tw.SLATE_300,
					tw.SLATE_400,
				)
				self.style.transform_origin = 0.5
				self.style.scale = 1 - 0.05 * self.transitions[1]
				self.transitions[1] +=
					(f32(i32(self.is_active)) - self.transitions[1]) * rate_per_second(7)
				self.transitions[0] +=
					(f32(i32(self.is_hovered)) - self.transitions[0]) * rate_per_second(7)
				if self.is_hovered {
					set_cursor(.Pointer)
				}
			},
		}, loc = loc)
}

do_frame :: proc() {
	MENU_ITEMS := []string {
		"Go to definition",
		"Go to declaration",
		"Find references",
		"Rename symbol",
		"Create macro",
		"Add/remove breakpoint",
		"Set as cold",
	}

	ctx := global_ctx
	kn.new_frame()

	begin()
	center := linalg.array_cast(kn.get_size(), f32) / 2
	begin_node(
		{
			p = 4,
			gap = 20,
			vertical = true,
			content_align_x = 0.5,
			content_align_y = 0.5,
			bg = kn.Color{0, 0, 0, 0},
			size = linalg.array_cast(kn.get_size(), f32),
		},
	)
	do_button(lucide.TRENDING_DOWN, font = &lucide.font, font_size = 20)
	do_button("Button")
	end_node()
	end()

	if ctx.is_debugging {
		kn.set_paint(kn.Black)
		text := kn.make_text(
			fmt.tprintf(
				"FPS: %.0f\n%.0f\n%v",
				kn.get_fps(),
				ctx.mouse_position,
				ctx.frame_duration,
			),
			14,
		)
		kn.add_box({0, text.size}, paint = kn.fade(kn.Black, 1.0))
		kn.add_text(text, 0, paint = kn.White)
	}

	kn.set_clear_color(kn.White)
	kn.present()

	free_all(context.temp_allocator)
}

