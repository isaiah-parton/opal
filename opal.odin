package opal

//
// TODO:
// 	[x] Figure out how to let a node modify its own size
// 		- Probably through callbacks
//
//

import kn "../katana"
import "base:runtime"
import "core:fmt"
import "core:io"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:sys/windows"
import "core:time"
import "core:unicode"
import "tedit"
import stbi "vendor:stb/image"

// Generic unique identifiers
Id :: u32

Box :: kn.Box

Vector2 :: [2]f32

RelativeVector2 :: struct {
	exact:    [2]f32,
	relative: [2]f32,
}

//
// **Padding**
//
// `{left, top, right, bottom}`
//
Padding :: [4]f32

Clip :: enum u8 {
	None,
	Partial,
	Full,
}

Cursor :: enum {
	Normal,
	Pointer,
	Text,
}

On_Set_Cursor_Proc :: #type proc(cursor: Cursor, data: rawptr) -> bool
On_Set_Clipboard_Proc :: #type proc(text: string, data: rawptr)
On_Get_Clipboard_Proc :: #type proc(data: rawptr) -> string

Mouse_Button :: enum {
	Left,
	Middle,
	Right,
}

Node_Config :: struct {
	p:               [4]f32,
	text:            string,
	pos:             [2]f32,
	relative_pos:    [2]f32,
	size:            [2]f32,
	max_size:        [2]f32,
	relative_size:   [2]f32,
	bounds:          Maybe(Box),
	bg:              Paint_Variant,
	stroke:          kn.Paint_Option,
	fg:              kn.Paint_Option,
	shadow_color:    kn.Color,
	font:            ^kn.Font,
	on_draw:         proc(_: ^Node),
	on_animate:      proc(_: ^Node),
	on_create:       proc(_: ^Node),
	on_drop:         proc(_: ^Node),
	on_add:          proc(_: ^Node),
	data:            rawptr,
	shadow_size:     f32,
	z:               u32,
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
	radius:          [4]f32,
	font_size:       f32,
	fit:             bool,
	fit_x:           bool,
	fit_y:           bool,
	grow:            bool,
	grow_x:          bool,
	grow_y:          bool,
	vertical:        bool,
	abs:             bool,
	wrap:            bool,
	clip:            bool,
	selectable:      bool,
	editable:        bool,
	root:            bool,
	widget:          bool,
}

node_configure :: proc(self: ^Node, config: Node_Config) {
	self.is_absolute = config.abs
	self.padding = {
		max(config.p.x, config.px, config.pl),
		max(config.p.y, config.py, config.pt),
		max(config.p.z, config.px, config.pr),
		max(config.p.w, config.py, config.pb),
	}
	self.is_widget = config.widget
	self.relative_position = config.relative_pos
	self.spacing = config.gap
	self.fit = {config.fit | config.fit_x, config.fit | config.fit_y}
	self.grow = {config.grow | config.grow_x, config.grow | config.grow_y}
	self.size = {max(config.size.x, config.w), max(config.size.y, config.h)}
	self.max_size = {max(config.max_size.x, config.max_w), max(config.max_size.y, config.max_h)}
	self.content_align = {config.content_align_x, config.content_align_y}
	self.align = {config.self_align_x, config.self_align_y}
	self.position = config.pos
	self.vertical = config.vertical
	self.style.shadow_size = config.shadow_size
	self.style.shadow_color = config.shadow_color
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
	self.on_create = config.on_create
	self.on_drop = config.on_drop
	self.relative_size = config.relative_size
	self.enable_wrapping = config.wrap
	self.clip_content = config.clip
	self.enable_selection = config.selectable
	self.enable_edit = config.editable
	self.z_index = config.z
	self.bounds = config.bounds
}

node_config_clone_of_parent :: proc(config: Node_Config) -> Node_Config {
	config := config
	config.abs = true
	config.relative_size = 1
	return config
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

	// Last frame on which this node was added
	frame:              int,

	// Unique identifier
	id:                 Id,

	// The `box` field represents the final position and size of the node and is only valid after `end()` has been called
	box:                Box,
	bounds:             Maybe(Box),

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

	// Where text is aligned within the box
	text_align:         [2]f32,

	// This is known after box is calculated
	text_origin:        [2]f32,

	// Values for the node's children layout
	padding:            [4]f32,
	content_align:      [2]f32,
	content_size:       [2]f32,
	growable_kid_count: int,
	spacing:            f32,
	vertical:           bool,
	is_absolute:        bool,
	enable_wrapping:    bool,

	// Marks the node as a clickable widget and will steal mouse events from the native window functionality
	is_widget:          bool,

	// Opal sacrifices one frame of responsiveness for faster frames. This value is a representation of the previous frame's input
	was_hovered:        bool,
	is_hovered:         bool,

	// True if any nodes below this one in the tree are hovered
	has_hovered_child:  bool,

	// Active state
	was_active:         bool,
	is_active:          bool,
	has_active_child:   bool,
	was_focused:        bool,
	is_focused:         bool,
	has_focused_child:  bool,

	// Times the node was clicked
	click_count:        u8,

	// Time of last mouse down event over this node
	last_click_time:    time.Time,

	// If overflowing content is clipped
	clip_content:       bool,

	// Interaction
	enable_selection:   bool,
	enable_edit:        bool,

	// Z index (higher values appear in front of lower ones)
	z_index:            u32,

	// If the node is hidden by clipping
	is_hidden:          bool,

	//
	time_created:       time.Time,

	// Appearance
	text:               string,
	text_layout:        kn.Selectable_Text,
	last_text_size:     [2]f32,
	style:              Node_Style,
	select_anchor:      int,
	editor:             tedit.Editor,
	transitions:        [3]f32,
	on_create:          proc(self: ^Node),
	on_drop:            proc(self: ^Node),
	on_animate:         proc(self: ^Node),
	on_draw:            proc(self: ^Node),
	on_add:             proc(self: ^Node),
	data:               rawptr,
	retained_data:      rawptr,
}

Color :: kn.Color

Image_Paint :: struct {
	index:  int,
	offset: [2]f32,
	size:   [2]f32,
}

Radial_Gradient :: struct {
	center: [2]f32,
	radius: f32,
	inner:  Color,
	outer:  Color,
}

Linear_Gradient :: struct {
	points: [2][2]f32,
	colors: [2]Color,
}

Paint_Variant :: union #no_nil {
	Color,
	Image_Paint,
	Radial_Gradient,
	Linear_Gradient,
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
	background_paint: Paint_Variant,
	foreground_paint: kn.Paint_Option,
	font:             ^kn.Font,
	shadow_color:     kn.Color,
	rotation:         f32,
	stroke_width:     f32,
	font_size:        f32,
	shadow_size:      f32,
	transform_kids:   bool,
}

User_Image :: struct {
	source: Maybe(Box),
	data:   rawptr,
	width:  i32,
	height: i32,
}

Context :: struct {
	// Input state
	mouse_position:             Vector2,
	last_mouse_position:        Vector2,
	mouse_button_down:          [Mouse_Button]bool,
	mouse_button_was_down:      [Mouse_Button]bool,
	key_down:                   [256]bool,
	key_was_down:               [256]bool,
	widget_hovered:             bool,
	hovered_node:               ^Node,
	focused_node:               ^Node,
	active_node:                ^Node,
	hovered_id:                 Id,
	focused_id:                 Id,
	active_id:                  Id,
	on_set_cursor:              On_Set_Cursor_Proc,
	on_set_clipboard:           On_Set_Clipboard_Proc,
	on_get_clipboard:           On_Get_Clipboard_Proc,
	callback_data:              rawptr,
	cursor:                     Cursor,
	last_cursor:                Cursor,
	selection_background_color: kn.Color,
	selection_foreground_color: kn.Color,
	frame:                      int,

	// User images
	images:                     [dynamic]Maybe(User_Image),

	// Call index
	call_index:                 int,

	// Nodes by call order
	node_by_id:                 map[Id]^Node,

	// Node memory is stored contiguously for memory efficiency
	nodes:                      [2048]Maybe(Node),

	// All nodes wihout a parent are stored here for layout solving
	// They are the root nodes of their layout trees
	roots:                      [dynamic]^Node,

	// The stack of nodes being declared
	stack:                      [dynamic]^Node,

	// The hash stack
	id_stack:                   [dynamic]Id,

	// The top-most element of the stack
	current_node:               ^Node,

	// Profiling state
	frame_start_time:           time.Time,
	frame_duration:             time.Duration,
	compute_start_time:         time.Time,
	compute_duration:           time.Duration,

	// How many frames are queued for drawing
	queued_frames:              int,

	// If the graphics backend should redraw the UI
	requires_redraw:            bool,

	// Debug state
	is_debugging:               bool,
}

// @(private)
global_ctx: ^Context

//
// Image helpers
//

load_image :: proc(file: string) -> (index: int, ok: bool) {
	ctx := global_ctx

	image: User_Image

	image.data = stbi.load(
		strings.clone_to_cstring(file, context.temp_allocator),
		&image.width,
		&image.height,
		nil,
		4,
	)
	if image.data == nil {
		return
	}

	ok = true

	for &slot, slot_index in ctx.images {
		if slot == nil {
			slot = image
			index = slot_index
			return
		}
	}

	index = len(ctx.images)
	append(&ctx.images, image)

	return
}

use_image :: proc(index: int) -> (source: Box, ok: bool) {
	ctx := global_ctx
	if index < 0 || index >= len(ctx.images) {
		return {}, false
	}
	#no_bounds_check image := (&ctx.images[index].?) or_return
	if image.source == nil {
		image.source = kn.copy_image_to_atlas(image.data, int(image.width), int(image.height))
	}
	return image.source.?
}

//
// Box helpers
//

box_width :: proc(box: Box) -> f32 {
	return box.hi.x - box.lo.x
}
box_height :: proc(box: Box) -> f32 {
	return box.hi.y - box.lo.y
}
box_center_x :: proc(box: Box) -> f32 {
	return (box.lo.x + box.hi.x) * 0.5
}
box_center_y :: proc(box: Box) -> f32 {
	return (box.lo.y + box.hi.y) * 0.5
}

box_size :: proc(box: Box) -> [2]f32 {
	return box.hi - box.lo
}

size_ratio :: proc(size: [2]f32, ratio: [2]f32) -> [2]f32 {
	return [2]f32 {
		max(size.x, size.y * (ratio.x / ratio.y)),
		max(size.y, size.x * (ratio.y / ratio.x)),
	}
}

// If `a` is inside of `b`
point_in_box :: proc(a: [2]f32, b: Box) -> bool {
	return (a.x >= b.lo.x) && (a.x < b.hi.x) && (a.y >= b.lo.y) && (a.y < b.hi.y)
}

// If `a` is touching `b`
box_touches_box :: proc(a, b: Box) -> bool {
	return (a.hi.x >= b.lo.x) && (a.lo.x <= b.hi.x) && (a.hi.y >= b.lo.y) && (a.lo.y <= b.hi.y)
}

// If `a` is contained entirely in `b`
box_contains_box :: proc(a, b: Box) -> bool {
	return (b.lo.x >= a.lo.x) && (b.hi.x <= a.hi.x) && (b.lo.y >= a.lo.y) && (b.hi.y <= a.hi.y)
}

// Get the clip status of `b` inside `a`
get_clip :: proc(a, b: Box) -> Clip {
	if a.lo.x > b.hi.x || a.hi.x < b.lo.x || a.lo.y > b.hi.y || a.hi.y < b.lo.y {
		return .Full
	}
	if a.lo.x >= b.lo.x && a.hi.x <= b.hi.x && a.lo.y >= b.lo.y && a.hi.y <= b.hi.y {
		return .None
	}
	return .Partial
}

// Updates `a` to fit `b` inside it
update_bounding :: proc(a, b: Box) -> Box {
	a := a
	a.lo = linalg.min(a.lo, b.lo)
	a.hi = linalg.max(a.hi, b.hi)
	return a
}

// Clamps `a` inside `b`
clamp_box :: proc(a, b: Box) -> Box {
	return {linalg.clamp(a.lo, b.lo, b.hi), linalg.clamp(a.hi, b.lo, b.hi)}
}

snapped_box :: proc(box: Box) -> Box {
	return Box{linalg.floor(box.lo), linalg.floor(box.hi)}
}

box_center :: proc(a: Box) -> [2]f32 {
	return {(a.lo.x + a.hi.x) * 0.5, (a.lo.y + a.hi.y) * 0.5}
}

//
// Hashing algorithm
//

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
	reserve(&ctx.roots, 64)
	reserve(&ctx.stack, 64)
	reserve(&ctx.id_stack, 64)
	ctx.queued_frames = 2
	ctx.selection_background_color = kn.LIGHT_GREEN
	ctx.selection_foreground_color = kn.BLACK
}

context_deinit :: proc(ctx: ^Context) {
	assert(ctx != nil)
	for &node in ctx.nodes {
		node := (&node.?) or_continue
		node_destroy(node)
	}
	delete(ctx.roots)
	delete(ctx.stack)
	delete(ctx.id_stack)
}

context_set_clipboard :: proc(ctx: ^Context, data: string) {
	if ctx.on_set_clipboard == nil {
		return
	}
	ctx.on_set_clipboard(data, ctx.callback_data)
}

set_clipboard :: proc(data: string) {
	context_set_clipboard(global_ctx, data)
}

//
// Animation helpers
//

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
	free(global_ctx)
	global_ctx = nil
}

//
// Call these from your event loop to handle input
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

handle_window_size_change :: proc(width, height: i32) {
	kn.set_size(width, height)
	draw_frames(1)
}

//
// Used to get current input state
//

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

key_down :: proc(key: int) -> bool {
	ctx := global_ctx
	return ctx.key_down[key]
}

key_pressed :: proc(key: int) -> bool {
	ctx := global_ctx
	return ctx.key_down[key] && !ctx.key_was_down[key]
}

key_released :: proc(key: int) -> bool {
	ctx := global_ctx
	return !ctx.key_down[key] && ctx.key_was_down[key]
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

	ctx.compute_start_time = time.now()

	clear(&ctx.id_stack)
	clear(&ctx.stack)
	clear(&ctx.roots)

	push_id(Id(FNV1A32_OFFSET_BASIS))
	ctx.current_node = nil
	ctx.hovered_node = nil
	ctx.focused_node = nil
	ctx.active_node = nil

	if ctx.mouse_button_down != ctx.mouse_button_was_down ||
	   ctx.mouse_position != ctx.last_mouse_position {
		draw_frames(2)
	}

	ctx.frame += 1
	ctx.call_index = 0
}

//
// Ends UI declaration and constructs the final layout, node boxes are only valid after this is called
//
end :: proc() {
	ctx := global_ctx

	if ctx.on_set_cursor != nil && ctx.cursor != ctx.last_cursor {
		if ctx.on_set_cursor(ctx.cursor, ctx.callback_data) {
			ctx.last_cursor = ctx.cursor
		}
	}
	ctx.cursor = .Normal

	// Process and draw the UI
	for root in ctx.roots {
		node_solve_sizes_recursively(root)
		node_solve_box_recursively(root)
	}

	ctx.widget_hovered = false
	if ctx.hovered_node != nil {
		ctx.hovered_id = ctx.hovered_node.id
		if ctx.hovered_node.is_widget {
			ctx.widget_hovered = true
		}
	} else {
		ctx.hovered_id = 0
	}
	if mouse_pressed(.Left) {
		if ctx.hovered_node != nil {
			ctx.focused_id = ctx.hovered_node.id
		} else {
			ctx.focused_id = 0
		}
	}
	if ctx.active_node != nil {
		ctx.active_id = ctx.active_node.id
	} else if mouse_released(.Left) {
		ctx.active_id = 0
	}

	for root in ctx.roots {
		node_propagate_input_recursively(root)
		node_draw_recursively(root)
	}

	kn.set_draw_order(0)

	// Clean up unused nodes
	for id, node in ctx.node_by_id {
		if node.is_dead {
			delete_key(&ctx.node_by_id, node.id)
			if node.on_drop != nil {
				node.on_drop(node)
			}
			node_destroy(node)
			(^Maybe(Node))(node)^ = nil
		} else {
			node.is_dead = true
		}
	}

	ctx.mouse_button_was_down = ctx.mouse_button_down
	ctx.last_mouse_position = ctx.mouse_position

	// Update redraw state
	ctx.requires_redraw = ctx.queued_frames > 0
	ctx.queued_frames = max(0, ctx.queued_frames - 1)

	ctx.compute_duration = time.since(ctx.compute_start_time)
}

set_cursor :: proc(cursor: Cursor) {
	global_ctx.cursor = cursor
}

draw_frames :: proc(how_many: int) {
	global_ctx.queued_frames = max(global_ctx.queued_frames, how_many)
}

requires_redraw :: proc() -> bool {
	return global_ctx.requires_redraw
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
	ctx.current_node = node
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
		background_paint = kn.BLACK,
		foreground_paint = kn.WHITE,
		stroke_paint = kn.DIM_GRAY,
		stroke_width = 1,
	}
}

text_node_style :: proc() -> Node_Style {
	return {stroke_width = 1}
}

//
// Get an existing node by its id or create a new one
//
get_or_create_node :: proc(id: Id) -> (result: ^Node) {
	ctx := global_ctx

	if node, ok := ctx.node_by_id[id]; ok {
		result = node
	} else {
		for &slot, slot_index in ctx.nodes {
			if slot == nil {
				ctx.nodes[slot_index] = Node {
					id           = id,
					time_created = time.now(),
				}
				result = &ctx.nodes[slot_index].?
				ctx.node_by_id[id] = result
				draw_frames(1)
				break
			}
		}
	}

	assert(result != nil)

	return
}

begin_node :: proc(config: Node_Config, loc := #caller_location) -> (self: ^Node) {
	ctx := global_ctx
	self = get_or_create_node(hash_loc(loc))

	if self.parent != ctx.current_node {
		self.parent = ctx.current_node
		assert(self != self.parent)
	}

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

do_node :: proc(config: Node_Config, loc := #caller_location) -> ^Node {
	self := begin_node(config, loc)
	end_node()
	return self
}

//
// Node logic
//

focus_node :: proc(id: Id) {
	global_ctx.focused_id = id
}

node_destroy :: proc(self: ^Node) {
	delete(self.kids)
}

node_update_this_frame_input :: proc(self: ^Node) {
	ctx := global_ctx

	self.was_hovered = self.is_hovered
	self.is_hovered = ctx.hovered_id == self.id

	self.was_active = self.is_active
	self.is_active = ctx.active_id == self.id

	self.was_focused = self.is_focused
	self.is_focused = ctx.focused_id == self.id
}

node_reset_propagated_input :: proc(self: ^Node) {
	self.has_hovered_child = false
	self.has_active_child = false
	self.has_focused_child = false
}

node_receive_propagated_input :: proc(self: ^Node, child: ^Node) {
	self.has_hovered_child = self.has_hovered_child | child.is_hovered | child.has_hovered_child
	self.has_active_child = self.has_active_child | child.is_active | child.has_active_child
	self.has_focused_child = self.has_focused_child | child.is_focused | child.has_focused_child
}

node_propagate_input_recursively :: proc(self: ^Node, depth := 0) {
	assert(depth < 128)
	node_reset_propagated_input(self)
	node_update_this_frame_input(self)
	for node in self.kids {
		node_propagate_input_recursively(node)
		node_receive_propagated_input(self, node)
	}
}

node_on_new_frame :: proc(self: ^Node, config: Node_Config) {
	ctx := global_ctx

	reserve(&self.kids, 16)
	clear(&self.kids)

	self.style.scale = 1

	self.z_index = 0

	// Configure the node
	node_configure(self, config)

	if config.root {
		self.parent = nil
	}

	// Keep alive this frame
	self.is_dead = false

	// Reset accumulative values
	self.content_size = 0

	// Create text layout
	if len(self.text) > 0 {
		if self.style.font == nil {
			self.style.font = &kn.DEFAULT_FONT
		}
		self.text_layout = kn.Selectable_Text {
			text = kn.make_text(self.text, self.style.font_size, self.style.font^),
		}
		self.content_size = linalg.max(
			self.content_size,
			self.text_layout.size,
			self.last_text_size,
		)
	}

	if self.on_add != nil {
		self.on_add(self)
	}

	//
	self.size += self.added_size

	// Root
	if self.parent == nil {
		append(&ctx.roots, self)
		return
	}

	// Child logic
	append(&self.parent.kids, self)

	if self.grow[int(self.parent.vertical)] {
		self.parent.growable_kid_count += 1
	}
}

node_on_child_end :: proc(self: ^Node, child: ^Node) {
	// Propagate content size up the tree in reverse breadth-first
	if child.is_absolute {
		return
	}
	if self.vertical {
		self.content_size.y += child.size.y
		self.content_size.x = max(self.content_size.x, child.size.x)
	} else {
		self.content_size.x += child.size.x
		self.content_size.y = max(self.content_size.y, child.size.y)
	}
}

node_solve_box :: proc(self: ^Node, offset: [2]f32) {
	self.box.lo = offset + self.position
	if bounds, ok := self.bounds.?; ok {
		self.box.lo = linalg.clamp(self.box.lo, bounds.lo, bounds.hi - self.size)
	}
	self.box.hi = self.box.lo + self.size

	node_receive_input(self)
}

node_solve_box_recursively :: proc(self: ^Node, offset: [2]f32 = {}) {
	node_solve_box(self, offset)
	for node in self.kids {
		node.z_index += self.z_index
		node_solve_box_recursively(node, self.box.lo)
		node_receive_propagated_input(self, node)
	}
}

node_solve_sizes :: proc(self: ^Node) {
	// Axis indices
	i := int(self.vertical)
	j := 1 - i
	// Compute available space
	remaining_space := self.size[i] - self.content_size[i]
	available_span := self.size[j] - self.padding[j] - self.padding[j + 2]
	// Temporary array of growable children
	growables := make(
		[dynamic]^Node,
		0,
		self.growable_kid_count,
		allocator = context.temp_allocator,
	)
	// Populate the array
	for &node in self.kids {
		if !node.is_absolute && node.grow[i] {
			append(&growables, node)
		}
	}
	// As long as there is space remaining and children to grow
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
		// Compute the smallest size to add
		size_to_add = min(second_smallest - smallest, remaining_space / f32(len(growables)))
		// Add that amount to every eligable child
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
	// Now compute each child's position within its parent
	offset_along_axis: f32 = self.padding[i]
	for node in self.kids {
		if node.is_absolute {
			node.position += self.size * node.relative_position
			node.size += self.size * node.relative_size
		} else {
			node.position[i] = offset_along_axis + remaining_space * self.content_align[i]
			if node.grow[j] {
				node.size[j] = max(node.size[j], available_span)
			}
			node.position[j] =
				self.padding[j] + (available_span - node.size[j]) * self.content_align[j]
			offset_along_axis += node.size[i] + self.spacing
		}
	}
}

node_solve_sizes_recursively :: proc(self: ^Node, depth := 1) {
	assert(depth < 128)
	node_solve_sizes(self)
	for node in self.kids {
		node_solve_sizes_recursively(node, depth + 1)
	}
}

node_receive_input :: proc(self: ^Node) {
	ctx := global_ctx
	if ctx.mouse_position.x >= self.box.lo.x &&
	   ctx.mouse_position.x <= self.box.hi.x &&
	   ctx.mouse_position.y >= self.box.lo.y &&
	   ctx.mouse_position.y <= self.box.hi.y {
		if !(ctx.hovered_node != nil && ctx.hovered_node.z_index > self.z_index) {
			ctx.hovered_node = self
		}
	}
	if self.is_hovered {
		if mouse_pressed(.Left) {
			// Set this node as the globally active one, `is_active` will be true next frame unless the active state is stolen
			ctx.active_node = self
			// Reset click counter if there was too much delay
			if time.since(self.last_click_time) > time.Millisecond * 450 {
				self.click_count = 0
			}
			self.click_count += 1
			self.last_click_time = time.now()
		}
	}
}

node_draw_recursively :: proc(self: ^Node, depth := 0) {
	assert(depth < 128)
	ctx := global_ctx

	last_transitions := self.transitions
	if self.on_animate != nil {
		self.on_animate(self)
	}

	// Detect changes in transition values
	if self.transitions != last_transitions &&
	   linalg.greater_than_array(self.transitions, 0.01) != {} {
		draw_frames(2)
	}

	// Compute text position
	self.text_origin =
		linalg.lerp(
			self.box.lo + self.padding.xy,
			self.box.hi - self.padding.zw,
			self.text_align,
		) -
		self.text_layout.size * self.text_align

	// Perform wrapping if enabled
	if self.text_layout.size.x > self.size.x && self.enable_wrapping {
		assert(self.style.font != nil)
		self.text_layout.text = kn.make_text(
			self.text,
			self.style.font_size,
			self.style.font^,
			wrap = .Words,
			max_size = {self.size.x, math.F32_MAX},
		)
		self.last_text_size = self.text_layout.size
	}

	// Compute text selection state if enabled
	if self.enable_selection {
		self.text_layout = kn.make_selectable(
			self.text_layout,
			ctx.mouse_position - self.text_origin,
			min(self.editor.selection[0], self.editor.selection[1]),
			max(self.editor.selection[0], self.editor.selection[1]),
		)
		if self.text_layout.contact.valid && self.is_hovered {
			set_cursor(.Text)
		}
		node_update_selection(self, self.text, &self.text_layout)
	}

	// Is transformation necessary?
	is_transformed :=
		self.style.scale != 1 || self.style.translate != 0 || self.style.rotation != 0

	// Perform transformations
	if is_transformed {
		transform_origin := self.box.lo + self.size * self.style.transform_origin
		kn.push_matrix()
		kn.translate(transform_origin)
		kn.rotate(self.style.rotation)
		kn.scale(self.style.scale)
		kn.translate(-transform_origin + self.style.translate)
	}

	// Apply clipping
	if self.clip_content {
		kn.push_scissor(kn.make_box(self.box, self.style.radius))
	}

	kn.set_draw_order(int(self.z_index))

	// Draw self
	if ctx.queued_frames > 0 {
		if self.on_draw != nil {
			self.on_draw(self)
		} else {
			node_draw_default(self)
		}
	}

	if is_transformed {
		kn.pop_matrix()
	}

	// Draw children
	for node in self.kids {
		node_draw_recursively(node, depth + 1)
	}

	if self.clip_content {
		kn.pop_scissor()
	}

	// Draw debug lines
	if ODIN_DEBUG {
		if ctx.is_debugging {
			if self.has_hovered_child {
				kn.add_box_lines(self.box, 1, self.style.radius, paint = kn.LIGHT_GREEN)
			} else if self.is_hovered {
				kn.add_box(self.box, self.style.radius, paint = kn.fade(kn.RED, 0.3))
			}
		}
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
	{
		switch v in self.style.background_paint {
		case kn.Color:
			kn.set_paint(v)
		case Image_Paint:
			size := box_size(self.box)
			if source, ok := use_image(v.index); ok {
				kn.set_paint(
					kn.make_atlas_sample(
						source,
						{self.box.lo + v.offset * size, self.box.lo + v.size * size},
						kn.WHITE,
					),
				)
			}
		case Radial_Gradient:
			kn.set_paint(
				kn.make_radial_gradient(
					self.box.lo + v.center * self.size,
					v.radius * max(self.size.x, self.size.y),
					v.inner,
					v.outer,
				),
			)
		case Linear_Gradient:
			kn.set_paint(
				kn.make_linear_gradient(
					self.box.lo + v.points[0] * self.size,
					self.box.lo + v.points[1] * self.size,
					v.colors[0],
					v.colors[1],
				),
			)
		}
		kn.add_box(self.box, self.style.radius)
	}
	if self.style.foreground_paint != nil && !kn.text_is_empty(&self.text_layout) {
		if self.enable_selection {
			draw_text_highlight(
				&self.text_layout,
				self.text_origin,
				global_ctx.selection_background_color,
			)
		}
		draw_text(
			&self.text_layout,
			self.text_origin,
			self.style.foreground_paint,
			global_ctx.selection_foreground_color,
		)
		if self.enable_edit {
			draw_text_layout_cursor(
				&self.text_layout,
				self.text_origin,
				global_ctx.selection_background_color,
			)
		}
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

draw_text_layout_cursor :: proc(text: ^kn.Selectable_Text, origin: [2]f32, color: kn.Color) {
	if len(text.glyphs) == 0 {
		return
	}
	line_height := text.font.line_height * text.font_scale
	cursor_origin := origin + text.glyphs[text.selection.first_glyph].offset
	kn.add_box(
		snapped_box(
			{
				{cursor_origin.x - 1, cursor_origin.y},
				{cursor_origin.x + 1, cursor_origin.y + line_height},
			},
		),
		paint = color,
	)
}

draw_text :: proc(
	text: ^kn.Selectable_Text,
	origin: [2]f32,
	paint: kn.Paint_Option,
	selected_color: kn.Color,
) {
	for &glyph, glyph_index in text.glyphs {
		if glyph.source.lo == glyph.source.hi {
			continue
		}
		kn.add_glyph(
			glyph,
			text.font_scale,
			origin + glyph.offset,
			paint = selected_color if (glyph_index >= text.selection.first_glyph && glyph_index < text.selection.last_glyph) else paint,
		)
	}
}

draw_text_highlight :: proc(text: ^kn.Selectable_Text, origin: [2]f32, color: kn.Color) {
	if text.selection.first_glyph == text.selection.last_glyph {
		return
	}
	line_height := text.font.line_height * text.font_scale
	for &line in text.lines {
		highlight_range := [2]int {
			max(text.selection.first_glyph, line.first_glyph),
			min(text.selection.last_glyph, line.last_glyph),
		}
		if highlight_range.x > highlight_range.y {
			continue
		}
		box := Box {
			origin + text.glyphs[highlight_range.x].offset,
			origin +
			text.glyphs[highlight_range.y].offset +
			{
					text.font.space_advance *
					text.font_scale *
					f32(i32(text.selection.last_glyph > line.last_glyph)),
					line_height,
				},
		}
		kn.add_box(
			snapped_box(box),
			3 *
			{
					f32(i32(text.selection.first_glyph >= line.first_glyph)),
					0,
					0,
					f32(i32(text.selection.last_glyph <= line.last_glyph)),
				},
			paint = color,
		)
	}
}

node_update_selection :: proc(self: ^Node, data: string, text: ^kn.Selectable_Text) {
	is_separator :: proc(r: rune) -> bool {
		return !unicode.is_alpha(r) && !unicode.is_number(r)
	}

	last_selection := self.editor.selection
	if self.is_active && text.contact.index >= 0 {
		if !self.was_active {
			self.select_anchor = text.contact.index
			if self.click_count == 3 {
				self.editor.selection = {len(data), 0}
			} else {
				self.editor.selection = {text.contact.index, text.contact.index}
			}
		}
		switch self.click_count {
		case 2:
			allow_precision := text.contact.index != self.select_anchor
			if text.contact.index <= self.select_anchor {
				self.editor.selection[0] =
					text.contact.index if (allow_precision && is_separator(rune(data[text.contact.index]))) else max(0, strings.last_index_proc(data[:min(text.contact.index, len(data))], is_separator) + 1)
				self.editor.selection[1] = strings.index_proc(
					data[self.select_anchor:],
					is_separator,
				)
				if self.editor.selection[1] == -1 {
					self.editor.selection[1] = len(data)
				} else {
					self.editor.selection[1] += self.select_anchor
				}
			} else {
				self.editor.selection[1] = max(
					0,
					strings.last_index_proc(data[:self.select_anchor], is_separator) + 1,
				)
				// `text.selection.index - 1` is safe as long as `text.selection.index > self.select_anchor`
				self.editor.selection[0] =
					0 if (allow_precision && is_separator(rune(data[text.contact.index - 1]))) else strings.index_proc(data[text.contact.index:], is_separator)
				if self.editor.selection[0] == -1 {
					self.editor.selection[0] = len(data)
				} else {
					self.editor.selection[0] += text.contact.index
				}
			}
		case 1:
			self.editor.selection[0] = text.contact.index
		}
	}
}

Input_Descriptor :: struct {
	data:      rawptr,
	type_info: ^runtime.Type_Info,
}

Input_State :: struct {
	editor:           tedit.Editor,
	builder:          strings.Builder,
	type_info:        runtime.Type_Info,
	match_list:       [dynamic]string,
	offset:           [2]f32,
	action_time:      time.Time,
	closest_match:    string,
	anchor:           int,
	last_mouse_index: int,
}

to_obfuscated_reader :: proc(reader: ^strings.Reader) -> io.Reader {
	return io.Reader(io.Stream {
		procedure = proc(
			data: rawptr,
			mode: io.Stream_Mode,
			p: []byte,
			_: i64,
			_: io.Seek_From,
		) -> (
			n: i64,
			err: io.Error,
		) {
			if mode == .Read {
				r := (^strings.Reader)(data)
				nn: int
				nn, err = strings.reader_read(r, p)
				if len(p) > 0 {
					p[0] = '*'
				}
				n = i64(min(nn, 1))
			}
			return
		},
		data = reader,
	})
}

string_from_rune :: proc(char: rune, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator = allocator)
	strings.write_rune(&b, char)
	return strings.to_string(b)
}

