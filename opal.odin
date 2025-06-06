package opal

//
// The following are features and optimizations that could be necessary depending on what features I deem a priority in the future. Only to be implemented if absolutely necessary and if they don't compromise the system's simplicity and low-level control, or add pointless overhead.
// 	- Abstract away the functional components of a Node (Descriptor, Retained_State, Transient_State) to allow for transient nodes wihout hashed ids or interaction logic. Flex layouts need only a descriptor and some transient state, while inline layouts need additional retained state for caching their size. Ids will become retained state as they are only required by interactive nodes.
//
// TODO:
// 	[X] Change from `parent` and `owner` to a more explicit `layout_parent` and `state_parent`
//  [ ] Add inner shadows (to katana)
//  [X] Wrapped wrapped layouts
// 	[X] Make the `Node` struct smalllerrr
// 		- Maybe by separating nodes from their style (yes definitely, there's no reason to duplicate that data for 100s of nodes)
//

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
import "tedit"
import "vendor:sdl3"
import stbi "vendor:stb/image"

INFINITY :: math.F32_MAX

MAX_TREE_DEPTH :: 128

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

Clip :: enum u8 {
	None,
	Partial,
	Full,
}

Cursor :: enum {
	Normal,
	Pointer,
	Text,
	Resize_NS,
	Resize_EW,
	Resize_NWSE,
	Resize_NESW,
	Move,
}

On_Set_Cursor_Proc :: #type proc(cursor: Cursor, data: rawptr) -> bool
On_Set_Clipboard_Proc :: #type proc(data: rawptr, text: string) -> bool
On_Get_Clipboard_Proc :: #type proc(data: rawptr) -> (string, bool)
On_Get_Screen_Size_Proc :: #type proc(data: rawptr) -> [2]f32

Node_Relative_Placement :: struct {
	node:            ^Node,
	relative_offset: [2]f32,
	exact_offset:    [2]f32,
	relative_size:   [2]f32,
	exact_size:      [2]f32,
}

Color :: kn.Color

fade :: kn.fade

mix :: kn.mix

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

User_Image :: struct {
	source: Maybe(Box),
	data:   rawptr,
	width:  i32,
	height: i32,
}

Stroke_Type :: enum {
	Inner,
	Both,
	Outer,
}

Paint_Option :: kn.Paint_Option

Font :: kn.Font

Node_Result :: Maybe(^Node)

/*
Rule_Background :: distinct Paint_Variant
Rule_Foreground :: distinct Paint_Option
Rule_Stroke :: distinct Paint_Option
Rule_Stroke_Width :: distinct f32
Rule_Radius :: distinct [4]f32
Rule_Transform_Origin :: distinct [2]f32
Rule_Scale :: distinct [2]f32
Rule_Translate :: distinct [2]f32
Rule_Rotate :: distinct f32
Rule_Font :: distinct ^Font
Rule_Font_Size :: distinct f32
Rule_Shadow_Color :: distinct Color
Rule_Shadow_Size :: distinct f32

Rule :: union #no_nil {
	Rule_Background,
	Rule_Foreground,
	Rule_Stroke,
	Rule_Stroke_Width,
	Rule_Radius,
	Rule_Transform_Origin,
	Rule_Scale,
	Rule_Translate,
	Rule_Rotate,
	Rule_Font,
	Rule_Font_Size,
	Rule_Shadow_Color,
	Rule_Shadow_Size,
}

Rules :: struct {
	background:       Rule_Background,
	foreground:       Rule_Foreground,
	stroke:           Rule_Stroke,
	stroke_width:     Rule_Stroke_Width,
	radius:           Rule_Radius,
	transform_origin: Rule_Transform_Origin,
	scale:            Rule_Scale,
	translate:        Rule_Translate,
	rotate:           Rule_Rotate,
	font:             Rule_Font,
	font_size:        Rule_Font_Size,
	shadow_color:     Rule_Shadow_Color,
	shadow_size:      Rule_Shadow_Size,
}
*/

Context_Color :: enum {
	Selection_Background,
	Selection_Foreground,
	Scrollbar_Background,
	Scrollbar_Foreground,
}

Context_Descriptor :: struct {
	// Platform-defined callbacks
	on_set_cursor:      On_Set_Cursor_Proc,
	on_set_clipboard:   On_Set_Clipboard_Proc,
	on_get_clipboard:   On_Get_Clipboard_Proc,
	on_get_screen_size: On_Get_Screen_Size_Proc,

	// User-defined data for callbacks
	callback_data:      rawptr,
}

Context :: struct {
	using descriptor:          Context_Descriptor,

	///
	/// Configuration
	///

	// Prevents sub-pixel positioning to make edges appear perfectly crisp, motion however will not be as smooth
	snap_to_pixels:            bool,

	//
	window_is_focused:         bool,

	// Additional frame delay
	frame_interval:            time.Duration,

	// Time of last drawn frame
	last_draw_time:            time.Time,

	// Time of last average
	last_average_time:         time.Time,
	frames_since_last_average: int,

	// Window size lol
	screen_size:               Vector2,

	// Current and previous state of mouse position
	mouse_position:            Vector2,
	last_mouse_position:       Vector2,

	// Mouse scroll input
	mouse_scroll:              Vector2,

	// Time of last mouse down event
	last_mouse_down_time:      time.Time,
	last_mouse_down_button:    Mouse_Button,

	// The mouse offset from the clicked node
	node_click_offset:         Vector2,

	// Current and previous states of mouse buttons
	mouse_button_down:         Mouse_Buttons,
	mouse_button_was_down:     Mouse_Buttons,

	// Current and previous state of keyboard
	key_down:                  [Keyboard_Key]bool,
	key_was_down:              [Keyboard_Key]bool,

	// If a widget is hovered which would prevent native window interaction
	widget_hovered:            bool,

	// Which node will receive scroll input
	scrollable_node:           ^Node,

	// Transient pointers to interacted nodes
	hovered_node:              ^Node,

	// Ids of interacted nodes
	hovered_id:                Id,
	focused_id:                Id,

	//
	node_activation:           Maybe(Node_Activation),

	// Private cursor state
	cursor:                    Cursor,
	last_cursor:               Cursor,

	// Global visual style
	colors:                    [Context_Color]Color,

	// Frame count
	frame:                     int,

	// Native text input
	text_input:                [dynamic]rune,

	// User images
	images:                    [dynamic]Maybe(User_Image),

	// Call index
	call_index:                int,

	// Nodes by call order
	node_by_id:                map[Id]^Node,

	// Node memory is stored contiguously for memory efficiency.
	// TODO: Implement a dynamic array
	nodes:                     [8192]Maybe(Node),

	// All nodes wihout a parent are stored here for layout solving.
	roots:                     [dynamic]^Node,

	// The layout tree
	layout_roots:              [dynamic]^Node,

	// The stack of nodes being declared. May contain multiple roots, as its only a way of keeping track of the nodes currently being invoked.
	node_stack:                [dynamic]^Node,

	// The hash stack
	id_stack:                  [dynamic]Id,

	// Non-interactive glyphs
	glyphs:                    [dynamic]Glyph,

	//
	text_agent:                Text_Agent,

	//
	// Styles
	//
	style_stack:               [dynamic]^Node_Style,
	style_array:               [dynamic]Node_Style,

	// The top-most element of the stack
	current_node:              ^Node,

	// Profiling state
	frame_start_time:          time.Time,
	frame_duration:            time.Duration,

	// Debug only.
	frame_duration_sum:        time.Duration,
	frame_duration_avg:        time.Duration,

	//
	interval_start_time:       time.Time,
	interval_duration:         time.Duration,

	//
	compute_start_time:        time.Time,
	compute_duration:          time.Duration,

	// Debug only.
	compute_duration_sum:      time.Duration,
	compute_duration_avg:      time.Duration,

	// How many nodes are hidden. Debug only.
	drawn_nodes:               int,

	// How many frames are queued for drawing
	queued_frames:             int,

	// If the graphics backend should redraw the UI
	active:                    bool,

	// Node inspector
	inspector:                 Inspector,
}

// @(private)
global_ctx: ^Context

push_style :: proc(style: Node_Style) {
	ctx := global_ctx
	append(&ctx.style_array, style)
}

pop_style :: proc() {

}

add_style :: proc(style: Node_Style) -> ^Node_Style {
	ctx := global_ctx
	append(&ctx.style_array, style)
	return &ctx.style_array[len(ctx.style_array) - 1]
}

set_color :: proc(which: Context_Color, value: Color) {
	global_ctx.colors[which] = value
}

// Load a user image to the next available slot
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

// Use an already loaded user image, copying it to the atlas if it wasn't yet
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

get_screen_box :: proc() -> Box {
	return {0, global_ctx.screen_size}
}

begin_text_view :: proc(desc: Text_View_Descriptor) -> Maybe(^Text_View) {
	return text_agent_begin_view(&global_ctx.text_agent, desc)
}

end_text_view :: proc() {
	text_agent_end_view(&global_ctx.text_agent)
}

get_current_text :: proc() -> (text: ^Text_View, ok: bool) {
	return text_agent_current_view(&global_ctx.text_agent)
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

box_shrink :: proc(self: Box, amount: f32) -> Box {
	return {self.lo + amount, self.hi - amount}
}

// If `a` is inside of `b`
point_in_box :: proc(point: [2]f32, box: Box) -> bool {
	return(
		(point.x >= box.lo.x) &&
		(point.x < box.hi.x) &&
		(point.y >= box.lo.y) &&
		(point.y < box.hi.y) \
	)
}

// If `a` is touching `b`
box_overlaps_other :: proc(self, other: Box) -> bool {
	return(
		(self.hi.x >= other.lo.x) &&
		(self.lo.x <= other.hi.x) &&
		(self.hi.y >= other.lo.y) &&
		(self.lo.y <= other.hi.y) \
	)
}

// If `a` is contained entirely in `b`
box_contains_other :: proc(self, other: Box) -> bool {
	return(
		(self.lo.x >= other.lo.x) &&
		(self.hi.x <= other.hi.x) &&
		(self.lo.y >= other.lo.y) &&
		(self.hi.y <= other.hi.y) \
	)
}

// Get the clip status of a box inside another
box_get_clip :: proc(self, other: Box) -> Clip {
	if self.lo.x >= other.lo.x &&
	   self.hi.x <= other.hi.x &&
	   self.lo.y >= other.lo.y &&
	   self.hi.y <= other.hi.y {
		return .None
	}
	if self.lo.x > other.hi.x ||
	   self.hi.x < other.lo.x ||
	   self.lo.y > other.hi.y ||
	   self.hi.y < other.lo.y {
		return .Full
	}
	return .Partial
}

// Get the clip status of a box inside a rounded box
box_get_rounded_clip :: proc(self, other: Box, radius: f32) -> Clip {
	if self.lo.x >= other.lo.x + radius &&
	   self.hi.x <= other.hi.x - radius &&
	   self.lo.y >= other.lo.y + radius &&
	   self.hi.y <= other.hi.y - radius {
		return .None
	}
	if self.lo.x > other.hi.x ||
	   self.hi.x < other.lo.x ||
	   self.lo.y > other.hi.y ||
	   self.hi.y < other.lo.y {
		return .Full
	}
	return .Partial
}

// Grow a box to fit another box inside it
box_grow_to_fit :: proc(self: ^Box, other: Box) {
	self.lo = linalg.min(self.lo, other.lo)
	self.hi = linalg.max(self.hi, other.hi)
}

// Returns the box clamped inside another
box_clamped :: proc(self, other: Box) -> Box {
	return {linalg.max(self.lo, other.lo), linalg.min(self.hi, other.hi)}
}

// Snap a box to a whole number position
box_snap :: proc(self: ^Box) {
	size := self.hi - self.lo
	self.lo = linalg.floor(self.lo)
	self.hi = self.lo + linalg.floor(size)
}

box_floored :: proc(self: Box) -> Box {
	return Box{linalg.floor(self.lo), linalg.floor(self.hi)}
}

box_center :: proc(self: Box) -> [2]f32 {
	return {(self.lo.x + self.hi.x) * 0.5, (self.lo.y + self.hi.y) * 0.5}
}

box_cut_left :: proc(self: ^Box, amount: f32) -> (res: Box) {
	left := min(self.lo.x + amount, self.hi.x)
	res = {self.lo, {left, self.hi.y}}
	self.lo.x = left
	return
}

box_cut_top :: proc(self: ^Box, amount: f32) -> (res: Box) {
	top := min(self.lo.y + amount, self.hi.y)
	res = {self.lo, {self.hi.x, top}}
	self.lo.y = top
	return
}

box_cut_right :: proc(self: ^Box, amount: f32) -> (res: Box) {
	right := max(self.lo.x, self.hi.x - amount)
	res = {{right, self.lo.y}, self.hi}
	self.hi.x = right
	return
}

box_cut_bottom :: proc(self: ^Box, amount: f32) -> (res: Box) {
	bottom := max(self.lo.y, self.hi.y - amount)
	res = {{self.lo.x, bottom}, self.hi}
	self.hi.y = bottom
	return
}

//
// Hashing algorithm
//

FNV1A32_OFFSET_BASIS :: 0x811c9dc5
FNV1A32_PRIME :: 0x01000193

fnv32a :: proc(data: []byte, seed: u32 = FNV1A32_OFFSET_BASIS) -> u32 {
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
	reserve(&ctx.node_stack, 64)
	reserve(&ctx.id_stack, 64)

	ctx.queued_frames = 2

	assert(ctx.on_get_screen_size != nil)
	ctx.screen_size = ctx.on_get_screen_size(ctx.callback_data)
}

context_deinit :: proc(ctx: ^Context) {
	assert(ctx != nil)
	for &node in ctx.nodes {
		node := (&node.?) or_continue
		node_destroy(node)
	}
	delete(ctx.roots)
	delete(ctx.node_stack)
	delete(ctx.id_stack)
}

context_set_clipboard :: proc(ctx: ^Context, text: string) {
	if ctx.on_set_clipboard == nil {
		return
	}
	ctx.on_set_clipboard(ctx.callback_data, text)
}

set_clipboard :: proc(text: string) {
	context_set_clipboard(global_ctx, text)
}

//
// Animation helpers
//

rate_per_second :: proc(rate: f32) -> f32 {
	ctx := global_ctx
	return f32(time.duration_seconds(ctx.interval_duration)) * rate
}

node_update_transition :: proc(self: ^Node, index: int, condition: bool, duration_seconds: f32) {
	assert(index >= 0 && index < len(self.transitions))
	rate: f32
	if duration_seconds <= 0 {
		rate = 1
	} else {
		rate = rate_per_second(1 / duration_seconds)
	}
	#no_bounds_check {
		if condition {
			self.transitions[index] = min(1, self.transitions[index] + rate)
		} else {
			self.transitions[index] = max(0, self.transitions[index] - rate)
		}
		if self.transitions[index] > 0 && self.transitions[index] < 1 {
			draw_frames(2)
		}
	}
}

//
// Global context proc wrappers
//

init :: proc(descriptor: Context_Descriptor) {
	global_ctx = new(Context)
	global_ctx.descriptor = descriptor
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

handle_window_lost_focus :: proc() {
	global_ctx.window_is_focused = false
	draw_frames(1)
}

handle_window_gained_focus :: proc() {
	global_ctx.window_is_focused = true
	draw_frames(1)
}

handle_mouse_motion :: proc(x, y: f32) {
	global_ctx.mouse_position = {x, y}
	draw_frames(2)
}

handle_mouse_scroll :: proc(x, y: f32) {
	global_ctx.mouse_scroll = {x, y}
	if key_down(.Left_Shift) || key_down(.Right_Shift) {
		global_ctx.mouse_scroll = global_ctx.mouse_scroll.yx
	}
	draw_frames(2)
}

handle_text_input :: proc(text: cstring) {
	for c in string(text) {
		append(&global_ctx.text_input, c)
	}
	draw_frames(1)
}

handle_key_repeat :: proc(key: Keyboard_Key) {
	ctx := global_ctx
	ctx.key_was_down[key] = false
	draw_frames(1)
}

handle_key_down :: proc(key: Keyboard_Key) {
	ctx := global_ctx
	ctx.key_down[key] = true
	draw_frames(1)
}

handle_key_up :: proc(key: Keyboard_Key) {
	ctx := global_ctx
	ctx.key_down[key] = false
	draw_frames(1)
}

handle_mouse_down :: proc(button: Mouse_Button) {
	ctx := global_ctx
	ctx.mouse_button_down += {button}
	ctx.last_mouse_down_button = button
	ctx.last_mouse_down_time = time.now()
	draw_frames(2)
}

handle_mouse_up :: proc(button: Mouse_Button) {
	ctx := global_ctx
	ctx.mouse_button_down -= {button}
	draw_frames(2)
}

handle_window_resize :: proc(width, height: i32) {
	kn.set_size(width, height)
	global_ctx.screen_size = {f32(width), f32(height)}
	draw_frames(2)
}

handle_window_move :: proc() {
	global_ctx.last_draw_time = time.now()
}

//
// Used to get current input state
//

mouse_down :: proc(button: Mouse_Button) -> bool {
	ctx := global_ctx
	return button in ctx.mouse_button_down
}

mouse_pressed :: proc(button: Mouse_Button) -> bool {
	ctx := global_ctx
	return button in ctx.mouse_button_down && button not_in ctx.mouse_button_was_down
}

mouse_released :: proc(button: Mouse_Button) -> bool {
	ctx := global_ctx
	return button not_in ctx.mouse_button_down && button in ctx.mouse_button_was_down
}

key_down :: proc(key: Keyboard_Key) -> bool {
	ctx := global_ctx
	return ctx.key_down[key]
}

key_pressed :: proc(key: Keyboard_Key) -> bool {
	ctx := global_ctx
	return ctx.key_down[key] && !ctx.key_was_down[key]
}

key_released :: proc(key: Keyboard_Key) -> bool {
	ctx := global_ctx
	return !ctx.key_down[key] && ctx.key_was_down[key]
}

ctx_on_input_received :: proc(ctx: ^Context) {
	// Resolve input state
	ctx.scrollable_node = nil
	ctx.hovered_node = nil

	for root in ctx.roots {
		node_receive_input_recursive(root)
	}
}

//
// Clear the UI construction state for a new frame
//
begin :: proc() {
	ctx := global_ctx

	// Update redraw state
	ctx.active = ctx.queued_frames > 0
	if ctx.active {
		ctx.last_draw_time = time.now()
	}
	ctx.queued_frames = max(0, ctx.queued_frames - 1)

	// Initial frame interval
	frame_interval := ctx.frame_interval

	// Cap framerate to 30 after a short period of inactivity
	if time.since(ctx.last_draw_time) > time.Millisecond * 200 {
		frame_interval = time.Second / 20
	}

	// Update durations
	if ctx.interval_start_time != {} {
		ctx.interval_duration = time.since(ctx.interval_start_time)
	}
	ctx.interval_start_time = time.now()

	// Sleep to limit framerate
	if ctx.interval_duration < frame_interval {
		time.sleep(frame_interval - ctx.interval_duration)
	}

	ctx.frame_start_time = time.now()

	//
	// Reset ID stack
	//
	clear(&ctx.id_stack)
	push_id(Id(FNV1A32_OFFSET_BASIS))

	ctx.frame += 1
	ctx.call_index = 0
	ctx.widget_hovered = false
	ctx.current_node = nil

	do_mouse_input_pass :=
		ctx.mouse_position != ctx.last_mouse_position ||
		ctx.mouse_button_down != ctx.mouse_button_was_down

	//
	// Process input received this frame
	//
	if do_mouse_input_pass {
		ctx_on_input_received(ctx)

		if !key_down(.Left) {
			ctx.text_agent.hovered_view = nil
		}

		if ctx.hovered_node != nil {
			node := ctx.hovered_node
			ctx.hovered_id = node.id

			if node.enable_selection && node.text_view != nil {
				// if point_in_box(ctx.mouse_position, node_get_text_box(node)) {
				ctx.text_agent.hovered_view = node.text_view
				// }
			}

			if node.interactive {
				ctx.widget_hovered = true
			}
		}

		text_agent_on_mouse_move(&ctx.text_agent, ctx.mouse_position)

		// Active nodes deactivate when the mouse leaves them
		if activation, ok := ctx.node_activation.?; ok {
			if ctx.hovered_id != activation.which && !activation.captured {
				ctx.node_activation = nil
			}

			if mouse_released(.Left) {
				ctx.node_activation = nil
			}
		}

		if mouse_released(.Left) {
			ctx.text_agent.hovered_view = nil
			text_agent_on_mouse_up(&ctx.text_agent)
		}

		if mouse_pressed(.Left) {
			// Individual node interaction
			if ctx.hovered_node != nil {
				// Set activation status
				ctx.node_activation = Node_Activation {
					which    = ctx.hovered_node.id,
					captured = ctx.hovered_node.sticky,
				}
				// Reset click counter if there was too much delay
				if time.since(ctx.hovered_node.last_click_time) > time.Millisecond * 300 {
					ctx.hovered_node.click_count = 0
				}
				ctx.hovered_node.click_count += 1
				ctx.node_click_offset = ctx.mouse_position - ctx.hovered_node.box.lo
				ctx.hovered_node.last_click_time = time.now()
				ctx.focused_id = ctx.hovered_node.id
			} else {
				ctx.focused_id = 0
			}

			text_agent_on_mouse_down(&ctx.text_agent, .Left)
		}

		if mouse_down(.Left) {
			text_agent_when_mouse_down(&ctx.text_agent)
		}
	}


	// Receive mouse wheel input
	if ctx.scrollable_node != nil {
		ctx.scrollable_node.target_scroll -= ctx.mouse_scroll * 24
	}

	// Propagate input
	// TODO: Can this be done only when necessary?
	for root in ctx.roots {
		node_propagate_input_recursive(root)
	}

	//
	// Reset the node tree for reconstruction
	//
	for id, node in ctx.node_by_id {
		if node.dead {
			// TODO: Uhhhhh
			// if ctx.focused_id == node.id && node.parent != nil && node.parent.group {
			// 	ctx.focused_id = node.parent.id
			// }
			delete_key(&ctx.node_by_id, node.id)
			node_destroy(node)
			(^Maybe(Node))(node)^ = nil
		} else {
			node.dead = true
			node.dirty = false
			if id == ctx.inspector.selected_id {
				ctx.inspector.inspected_node = node^
			}
		}
	}

	//
	// Catch problems before they cause undefined behavior
	//
	assert(len(ctx.style_stack) == 0)
	assert(len(ctx.node_stack) == 0)

	//
	// Reset for new frame
	//
	text_agent_on_new_frame(&ctx.text_agent)

	clear(&ctx.roots)
	clear(&ctx.layout_roots)
	clear(&ctx.style_array)
	clear(&ctx.glyphs)
}

end :: proc() {
	ctx := global_ctx

	ctx.frame_duration = time.since(ctx.frame_start_time)

	if key_down(.Left_Control) && key_pressed(.C) {
		set_clipboard(text_agent_get_selection_string(&ctx.text_agent))
	}

	// Compute performance averages
	when ODIN_DEBUG {
		if time.since(ctx.last_average_time) >= time.Second {
			ctx.last_average_time = time.now()
			ctx.frames_since_last_average = max(ctx.frames_since_last_average, 1)
			ctx.compute_duration_avg = time.Duration(
				f64(ctx.compute_duration_sum) / f64(ctx.frames_since_last_average),
			)
			ctx.frame_duration_avg = time.Duration(
				f64(ctx.frame_duration_sum) / f64(ctx.frames_since_last_average),
			)
			ctx.frames_since_last_average = 0
			ctx.compute_duration_sum = 0
			ctx.frame_duration_sum = 0
			draw_frames(int(ctx.inspector.shown))
		}
		ctx.frames_since_last_average += 1
		ctx.compute_duration_sum += ctx.compute_duration
		ctx.frame_duration_sum += ctx.frame_duration
	}

	clear(&ctx.text_input)

	// Include built-in UI
	if key_down(.Left_Control) && key_down(.Left_Shift) && key_pressed(.I) {
		ctx.inspector.shown = !ctx.inspector.shown
	}
	if ctx.inspector.shown {
		inspector_show(&ctx.inspector)
	}

	when ODIN_DEBUG {
		ctx.drawn_nodes = 0
	}

	ctx.compute_start_time = time.now()
	ctx_solve_sizes(ctx)
	if ctx.active {
		ctx_solve_positions_and_draw(ctx)
	}

	//
	// Draw debug widgets
	//
	if self, ok := ctx.node_by_id[ctx.inspector.inspected_id]; ok {
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
			box := self.box
			padding_paint := kn.paint_index_from_option(Color{0, 0, 255, 128})
			if self.padding.x > 0 {
				kn.add_box(box_cut_left(&box, self.padding.x), paint = padding_paint)
			}
			if self.padding.y > 0 {
				kn.add_box(box_cut_top(&box, self.padding.y), paint = padding_paint)
			}
			if self.padding.z > 0 {
				kn.add_box(box_cut_right(&box, self.padding.z), paint = padding_paint)
			}
			if self.padding.w > 0 {
				kn.add_box(box_cut_bottom(&box, self.padding.w), paint = padding_paint)
			}
			kn.add_box(box, paint = Color{0, 255, 0, 100})
			kn.add_box_lines(self.box, 1, paint = Color{0, 255, 0, 255})
		}
	}

	if ctx.text_agent.hovered_view != nil {
		set_cursor(.Text)
	}

	if ctx.on_set_cursor != nil && ctx.cursor != ctx.last_cursor {
		if ctx.on_set_cursor(ctx.cursor, ctx.callback_data) {
			ctx.last_cursor = ctx.cursor
		}
	}
	ctx.cursor = .Normal

	ctx.mouse_button_was_down = ctx.mouse_button_down
	ctx.last_mouse_position = ctx.mouse_position
	ctx.key_was_down = ctx.key_down
	ctx.mouse_scroll = 0

	ctx.compute_duration = time.since(ctx.compute_start_time)
}

ctx_solve_sizes :: proc(self: ^Context) {
	for root in self.layout_roots {
		if !root.dirty {
			continue
		}
		if root.absolute {
			assert(root.layout_parent != nil)
			root.size += root.layout_parent.size * root.relative_size
		}
		if node_solve_sizes_and_wrap_recursive(root) {
			node_solve_sizes_recursive(root)
		}
	}
}

ctx_solve_positions_and_draw :: proc(self: ^Context) {
	for root in self.roots {
		node_solve_box_recursive(root, root.dirty)
	}

	for root in self.roots {
		node_draw_recursive(root)
	}
}

set_cursor :: proc(cursor: Cursor) {
	global_ctx.cursor = cursor
}

draw_frames :: proc(how_many: int) {
	global_ctx.queued_frames = max(global_ctx.queued_frames, how_many)
}

is_frame_active :: proc() -> bool {
	return global_ctx.active
}

//
// Attempt to overwrite the currently hovered node respecting z-index
//
// The memory pointed to by `node` must live until the next frame
//
try_hover_node :: proc(node: ^Node) {
	ctx := global_ctx
	if ctx.hovered_node != nil && ctx.hovered_node.layer > node.layer {
		return
	}
	ctx.hovered_node = node
}

default_node_style :: proc() -> Node_Style {
	return {background = kn.BLACK, foreground = kn.WHITE, stroke = kn.DIM_GRAY, stroke_width = 1}
}

text_node_style :: proc() -> Node_Style {
	return {stroke_width = 1}
}

//
// Get an existing node by its id or create a new one
//
get_or_create_node :: proc(id: Id) -> Maybe(^Node) {
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

begin_node :: proc(descriptor: ^Node_Descriptor, loc := #caller_location) -> (self: Node_Result) {
	ctx := global_ctx
	self = get_or_create_node(hash_loc(loc))

	if self, ok := self.?; ok {
		if descriptor != nil {
			self.descriptor = descriptor^
		}

		if self.absolute || ctx.current_node == nil {
			self.position = self.exact_offset
		}
		self.size = self.min_size

		if !self.is_root {
			self.parent = ctx.current_node
			self.layout_parent = self.parent
			assert(self != self.parent)
		}

		if self.parent == nil {
			begin_text_view({id = self.id})
		}

		node_on_new_frame(self)
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

	if self.fit != {} {
		self.size = linalg.max(self.size, self.content_size * self.fit)

		if self.square_fit {
			self.size = max(self.size.x, self.size.y)
		}
	}

	//
	// Determine dirty state from size changes in known metrics
	//
	if self.size != self.last_size || self.relative_size != self.last_relative_size {
		self.dirty = true
		self.last_size = self.size
		self.last_relative_size = self.relative_size
		draw_frames(1)
	} else {
		self.size = self.cached_size
	}

	//
	// Handle scrolling
	//

	// Update scroll
	node_update_scroll(self)

	// Add scrollbars
	if self.show_scrollbars && self.overflow != {} {
		SCROLLBAR_SIZE :: 3
		SCROLLBAR_PADDING :: 2

		inner_box := box_shrink(self.box, 1)

		push_id(self.id)

		scrollbar_style := Node_Style {
			background = ctx.colors[.Scrollbar_Background],
			foreground = ctx.colors[.Scrollbar_Foreground],
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
					relative_size = {0, 1},
					min_size = {SCROLLBAR_SIZE, SCROLLBAR_PADDING * -2 - corner_space},
					interactive = true,
					style = scrollbar_style,
					on_draw = scrollbar_on_draw,
					vertical = true,
				},
			).?
			added_size := SCROLLBAR_SIZE * node.transitions[1]
			node.min_size.x += added_size
			node.exact_offset.x -= added_size
			node.radius = node.min_size.x / 2
		}

		if self.overflow.x > 0 {
			node := add_node(
				&{
					absolute = true,
					data = self,
					relative_offset = {0, 1},
					exact_offset = {SCROLLBAR_PADDING, -SCROLLBAR_SIZE - SCROLLBAR_PADDING},
					relative_size = {1, 0},
					min_size = {-SCROLLBAR_PADDING * 2 - corner_space, SCROLLBAR_SIZE},
					interactive = true,
					style = scrollbar_style,
					on_draw = scrollbar_on_draw,
				},
			).?
			added_size := SCROLLBAR_SIZE * 2 * node.transitions[1]
			node.size.y += added_size
			node.position.y -= added_size
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

scrollbar_on_draw :: proc(self: ^Node) {
	assert(self.data != nil)

	owner := (^Node)(self.data)

	node_update_transition(self, 0, true, 0.1)
	node_update_transition(self, 1, self.is_hovered || self.is_active, 0.1)

	i := int(self.vertical)
	j := 1 - i

	inner_box := Box{self.box.lo + self.padding.xy, self.box.hi - self.padding.zw}
	length := max((inner_box.hi[i] - inner_box.lo[i]) * owner.size[i] / owner.content_size[i], 30)

	scroll_travel := max(owner.content_size[i] - owner.size[i], 0)
	scroll_time := owner.scroll[i] / scroll_travel

	thumb_travel := (inner_box.hi[i] - inner_box.lo[i]) - length

	thumb_box := Box{inner_box.lo, {}}
	thumb_box.lo[i] += thumb_travel * scroll_time
	thumb_box.hi[i] = thumb_box.lo[i] + length
	thumb_box.hi[j] = inner_box.hi[j]

	kn.add_box(
		box_clamped(thumb_box, self.box),
		(thumb_box.hi[j] - thumb_box.lo[j]) / 2,
		paint = self.style.foreground,
	)

	if self.is_active {
		if !self.was_active {
			if point_in_box(global_ctx.mouse_position, thumb_box) {
				global_ctx.node_click_offset = global_ctx.mouse_position - thumb_box.lo
			} else {
				global_ctx.node_click_offset = box_size(thumb_box) / 2
			}
		}

		owner.scroll[i] =
			clamp(
				(global_ctx.mouse_position[i] -
					(inner_box.lo[i] + global_ctx.node_click_offset[i])) /
				thumb_travel,
				0,
				1,
			) *
			scroll_travel

		owner.target_scroll[i] = owner.scroll[i]
	}
}

//
// Node logic
//

focus_node :: proc(id: Id) {
	global_ctx.focused_id = id
}

string_from_rune :: proc(char: rune, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator = allocator)
	strings.write_rune(&b, char)
	return strings.to_string(b)
}

