package opal

import kn "../katana"
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
import "lucide"
import tw "tailwind_colors"
import "tedit"
import "vendor:sdl3"
import stbi "vendor:stb/image"

INFINITY :: math.F32_MAX

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
	Dragging,
}

Keyboard_Key :: enum i32 {
	Zero,
	One,
	Two,
	Three,
	Four,
	Five,
	Six,
	Seven,
	Eight,
	Nine,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	Tab,
	Space,
	Left_Control,
	Left_Alt,
	Left_Shift,
	Right_Control,
	Right_Alt,
	Right_Shift,
	Menu,
	Escape,
	Enter,
	Backspace,
	Delete,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
}

On_Set_Cursor_Proc :: #type proc(cursor: Cursor, data: rawptr) -> bool
On_Set_Clipboard_Proc :: #type proc(data: rawptr, text: string) -> bool
On_Get_Clipboard_Proc :: #type proc(data: rawptr) -> (string, bool)
On_Get_Screen_Size_Proc :: #type proc(data: rawptr) -> [2]f32

Mouse_Button :: enum {
	Left,
	Middle,
	Right,
}

Node_Relative_Placement :: struct {
	node:            ^Node,
	relative_offset: [2]f32,
	exact_offset:    [2]f32,
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
	font:             ^Font,
	shadow_color:     Color,
	stroke_width:     f32,
	font_size:        f32,
	shadow_size:      f32,
}

//
// The transient data belonging to a node for only the frame's duration. This is reset every frame when the node is invoked.  Many of these values change as the UI tree is built.
//
Node_Descriptor :: struct {
	using style:             Node_Style,

	// The text content to be displayed in place of children
	text:                    string,

	// Z index (higher values appear in front of lower ones), this value stacks down the tree
	z_index:                 u32,

	// The node's final box will be loosely bound within this box, maintaining its size
	bounds:                  Maybe(Box),

	// The node's local position within its parent; or screen position if its a root
	position:                [2]f32,

	// Relative placement
	node_relative_placement: Maybe(Node_Relative_Placement),

	// Added position relative to parent size
	relative_position:       [2]f32,

	// The maximum size the node is allowed to grow to
	max_size:                [2]f32,

	// The node's actual size, this is subject to change until the end of the frame. The initial value is effectively the node's minimum size
	size:                    [2]f32,

	// Added size relative to the parent size
	relative_size:           [2]f32,

	// If the node will be grown to fill available space
	grow:                    [2]bool,

	// If the node will grow to acommodate its contents
	fit:                     [2]f32,

	// How the node is aligned on its origin if it is absolutely positioned
	align:                   [2]f32,

	// Spacing added between children
	spacing:                 f32,

	// If this node will treat its children's state as its own
	inherit_state:           bool,

	// If the node's children are arranged vertically
	vertical:                bool,

	// If true, the node will ignore the normal layout behavior and simply be positioned and sized relative to its parent
	is_absolute:             bool,

	// If text will be wrapped for the next frame
	enable_wrapping:         bool,

	// Marks the node as a clickable widget and will steal mouse events from the native window functionality
	is_widget:               bool,

	// When true, causes the node to not be adopted by the node before it. It will instead be added as a new root.
	is_root:                 bool,

	// If overflowing content is clipped
	clip_content:            bool,

	// If text content can be selected and copied
	enable_selection:        bool,

	// If text content can be edited
	enable_edit:             bool,

	// If newlines can be added to the text content
	is_multiline:            bool,

	// Disallows inspection in the debug inspector
	disable_inspection:      bool,

	// Show/hide scrollbars when content overflows
	show_scrollbars:         bool,

	// Values for the node's children layout
	padding:                 [4]f32,

	// How the content will be aligned if there is extra space
	content_align:           [2]f32,

	// An optional node that will behave as if it were this node's parent, when it doesn't in fact have one. Input state will be transfered to the owner.
	owner:                   ^Node,

	//
	// Callbacks for custom look or behavior
	//

	// Called just before the node is drawn, gives the user a chance to modify the node's style or apply animations based on its state
	on_animate:              proc(self: ^Node),

	// Called when the node is first initialized, allocate any additional state here
	on_create:               proc(self: ^Node),

	// Called when the node is discarded, this is to allow the user to clean up any custom state
	on_drop:                 proc(self: ^Node),

	// Called after the default drawing behavior
	on_draw:                 proc(self: ^Node),

	// Data for use in callbacks, this data should live from the invocation of this node until the UI is ended.
	data:                    rawptr,
}

//
// Generic UI nodes, everything is a made out of these
//
Node :: struct {
	using descriptor:        Node_Descriptor,

	// Node tree references
	parent:                  ^Node,

	// All nodes invoked between `begin_node` and `end_node`
	kids:                    [dynamic]^Node,

	// All growable children
	growable_kids:           [dynamic]^Node,

	// A simple kill switch that causes the node to be discarded
	is_dead:                 bool,

	// Last frame on which this node was invoked
	frame:                   int,

	// Unique identifier
	id:                      Id `fmt:"x"`,

	// The `box` field represents the final position and size of the node and is only valid after `end()` has been called
	box:                     Box,

	// The previous calculated size
	last_size:               [2]f32,

	// This is known after box is calculated
	text_origin:             [2]f32,

	// This is computed as the minimum space required to fit all children or the node's text content
	content_size:            [2]f32,

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
	builder:                 strings.Builder,

	// Interaction
	is_toggled:              bool,
	was_confirmed:           bool,
	was_changed:             bool,

	// The timestamp of the node's initialization in the context's arena
	time_created:            time.Time,

	// Text content
	text_layout:             kn.Selectable_Text `fmt:"-"`,
	last_text_size:          [2]f32,

	// View offset of contents
	scroll:                  [2]f32,
	target_scroll:           [2]f32,

	// Needs scissor
	has_clipped_child:       bool,

	// Text editing state
	editor:                  tedit.Editor,
	last_selection:          [2]int,

	// Universal state transition values for smooth animations
	transitions:             [3]f32,

	// Data intended to live as long as the node does. DO NOT manually free this data.
	owned_data:              rawptr,
}

Scope :: struct {
	data:      rawptr,
	type_info: runtime.Type_Info,
}

push_scope :: proc(value: any) {
	ctx := global_ctx
	scope := Scope {
		type_info = type_info_of(value.id),
	}
	scope.data = mem.arena_alloc(&ctx.scope_arena, scope.type_info.size)
	mem.copy(scope.data, value.data, scope.type_info.size)
	append(&ctx.scopes, scope)
	append(&ctx.scope_stack, &ctx.scopes[len(ctx.scopes) - 1])
}

pop_scope :: proc() {
	pop(&ctx.scope_stack)
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
	using descriptor:           Context_Descriptor,

	///
	/// Configuration
	///

	// Prevents sub-pixel positioning to make edges appear perfectly crisp, motion however will not be as smooth
	// TODO: Implement this
	snap_to_pixels:             bool,

	// Additional frame delay
	frame_interval:             time.Duration,

	// Time of last drawn frame
	last_draw_time:             time.Time,

	// Input state
	screen_size:                Vector2,

	// Current and previous state of mouse position
	mouse_position:             Vector2,
	last_mouse_position:        Vector2,

	// Mouse scroll input
	mouse_scroll:               Vector2,

	// The mouse offset from the clicked node
	node_click_offset:          Vector2,

	// Current and previous states of mouse buttons
	mouse_button_down:          [Mouse_Button]bool,
	mouse_button_was_down:      [Mouse_Button]bool,

	// Current and previous state of keyboard
	key_down:                   [Keyboard_Key]bool,
	key_was_down:               [Keyboard_Key]bool,

	// If a widget is hovered which would prevent native window interaction
	widget_hovered:             bool,

	// Which node will receive scroll input
	scrollable_node:            ^Node,

	// Transient pointers to interacted nodes
	hovered_node:               ^Node,
	focused_node:               ^Node,
	active_node:                ^Node,

	// Ids of interacted nodes
	hovered_id:                 Id,
	focused_id:                 Id,
	active_id:                  Id,

	// Private cursor state
	cursor:                     Cursor,
	last_cursor:                Cursor,

	// Global visual style
	selection_background_color: kn.Color,
	selection_foreground_color: kn.Color,

	// Frame count
	frame:                      int,

	// Native text input
	runes:                      [dynamic]rune,

	// User images
	images:                     [dynamic]Maybe(User_Image),

	// Call index
	call_index:                 int,

	// Nodes by call order
	node_by_id:                 map[Id]^Node,

	// Node memory is stored contiguously for memory efficiency.
	// TODO: Implement a dynamic arena because Opal currently crashes once there's no more slots available. (Maybe `begin_node` should be able to fail?)
	nodes:                      [4096]Maybe(Node),

	// All nodes wihout a parent are stored here for layout solving.
	roots:                      [dynamic]^Node,

	// The stack of nodes being declared. May contain multiple roots, as its only a way of keeping track of the nodes currently being invoked.
	stack:                      [dynamic]^Node,

	// The hash stack
	id_stack:                   [dynamic]Id,

	//
	scopes:                     [dynamic]Scope,

	// Scope stack
	scope_stack:                [dynamic]^Scope,
	scope_arena:                mem.Arena,
	scope_data:                 []u8,

	// The top-most element of the stack
	current_node:               ^Node,

	// Profiling state
	frame_start_time:           time.Time,
	frame_duration:             time.Duration,
	interval_start_time:        time.Time,
	interval_duration:          time.Duration,
	compute_start_time:         time.Time,
	compute_duration:           time.Duration,

	// How many frames are queued for drawing
	queued_frames:              int,

	// If the graphics backend should redraw the UI
	requires_redraw:            bool,

	// Node inspector
	inspector:                  Inspector,
}

// @(private)
global_ctx: ^Context

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

// Get the clip status of `b` inside `a`
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

// Updates `a` to fit `b` inside it
box_grow_to_fit :: proc(self: ^Box, other: Box) {
	self.lo = linalg.min(self.lo, other.lo)
	self.hi = linalg.max(self.hi, other.hi)
}

// Clamps `a` inside `b`
box_shrink_to_fit_inside :: proc(self, other: Box) -> Box {
	return {linalg.clamp(self.lo, other.lo, other.hi), linalg.clamp(self.hi, other.lo, other.hi)}
}

box_snap :: proc(self: ^Box) {
	size := self.hi - self.lo
	self.lo = linalg.round(self.lo)
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
	assert(ctx.on_get_screen_size != nil)
	ctx.screen_size = ctx.on_get_screen_size(ctx.callback_data)

	// Scope allocation
	ctx.scope_data = make([]u8, 2048)
	mem.arena_init(&ctx.scope_arena, ctx.scope_data)
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
		append(&global_ctx.runes, c)
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
	ctx.mouse_button_down[button] = true
	draw_frames(2)
}

handle_mouse_up :: proc(button: Mouse_Button) {
	ctx := global_ctx
	ctx.mouse_button_down[button] = false
	draw_frames(2)
}

handle_window_resize :: proc(width, height: i32) {
	kn.set_size(width, height)
	global_ctx.screen_size = {f32(width), f32(height)}
	draw_frames(1)
}

handle_window_move :: proc() {
	global_ctx.last_draw_time = time.now()
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

//
// Clear the UI construction state for a new frame
//
begin :: proc() {
	ctx := global_ctx

	// Update redraw state
	ctx.requires_redraw = ctx.queued_frames > 0
	if ctx.requires_redraw {
		ctx.last_draw_time = time.now()
	}
	ctx.queued_frames = max(0, ctx.queued_frames - 1)

	// Update durations
	if ctx.frame_start_time != {} {
		ctx.frame_duration = time.since(ctx.frame_start_time)
	}
	if ctx.interval_start_time != {} {
		ctx.interval_duration = time.since(ctx.interval_start_time)
	}
	ctx.interval_start_time = time.now()

	// Initial frame interval
	frame_interval := ctx.frame_interval

	// Cap framerate to 30 after a short period of inactivity
	if time.since(ctx.last_draw_time) > time.Millisecond * 500 {
		frame_interval = time.Second / 20
	}

	// Sleep to limit framerate
	time.sleep(max(0, frame_interval - ctx.frame_duration))

	// Reset timestamps
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
	ctx.scrollable_node = nil

	ctx.frame += 1
	ctx.call_index = 0
}

//
// Ends UI declaration and constructs the final layout, node boxes are only up-to-date after this is called.
//
// The UI computation sequence after construction is:
// 1. Solve sizes
// 2. Compute boxes and receive input
// 3. Propagate input up node trees
// 4. Draw
//
end :: proc() {
	ctx := global_ctx

	// Include built-in UI
	if key_down(.Left_Control) && key_down(.Left_Shift) && key_pressed(.I) {
		ctx.inspector.shown = !ctx.inspector.shown
	}
	if ctx.inspector.shown {
		inspector_show(&ctx.inspector)
	}

	clear(&ctx.runes)

	if ctx.on_set_cursor != nil && ctx.cursor != ctx.last_cursor {
		if ctx.on_set_cursor(ctx.cursor, ctx.callback_data) {
			ctx.last_cursor = ctx.cursor
		}
	}
	ctx.cursor = .Normal

	// Process and draw the UI
	for root in ctx.roots {
		node_solve_sizes_recursively(root)
		if placement, ok := root.node_relative_placement.?; ok {
			root.position =
				placement.node.box.lo +
				placement.node.size * placement.relative_offset +
				placement.exact_offset
		}
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
	ctx.key_was_down = ctx.key_down
	ctx.mouse_scroll = 0

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
	return {background = kn.BLACK, foreground = kn.WHITE, stroke = kn.DIM_GRAY, stroke_width = 1}
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

begin_node :: proc(descriptor: ^Node_Descriptor, loc := #caller_location) -> (self: ^Node) {
	ctx := global_ctx
	self = get_or_create_node(hash_loc(loc))

	if descriptor != nil {
		self.descriptor = descriptor^
	}

	if !self.is_root && self.parent != ctx.current_node {
		self.parent = ctx.current_node
		assert(self != self.parent)
	}

	node_on_new_frame(self)
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
	self.size = linalg.max(self.size, self.content_size * self.fit)

	// Add scrollbars
	if self.show_scrollbars {
		SCROLLBAR_SIZE :: 8
		SCROLLBAR_PADDING :: 2
		inner_box := box_shrink(self.box, 1)
		push_id(self.id)
		if self.content_size.y > self.last_size.y {
			do_node(
				&{
					is_absolute = true,
					relative_position = {1, 0},
					position = {-SCROLLBAR_SIZE - SCROLLBAR_PADDING, SCROLLBAR_PADDING},
					relative_size = {0, 1},
					size = {SCROLLBAR_SIZE, -SCROLLBAR_PADDING * 2},
					background = tw.NEUTRAL_600,
					foreground = tw.NEUTRAL_800,
					radius = SCROLLBAR_SIZE / 2,
					z_index = 1,
					data = self,
					on_draw = proc(self: ^Node) {
						parent := (^Node)(self.data)
						inner_box := self.box
						length := box_height(inner_box) * parent.size.y / parent.content_size.y
						scroll_travel := max(parent.content_size.y - parent.size.y, 0)
						scroll_time := parent.scroll.y / scroll_travel
						thumb_travel := box_height(inner_box) - length
						thumb_box := Box {
							{inner_box.lo.x, inner_box.lo.y + thumb_travel * scroll_time},
							{inner_box.hi.x, 0},
						}
						thumb_box.hi.y = thumb_box.lo.y + length
						kn.add_box(
							thumb_box,
							box_width(thumb_box) / 2,
							paint = self.style.foreground,
						)
						if self.is_active {
							parent.scroll.y =
								clamp(
									(global_ctx.mouse_position.y - inner_box.lo.y) / thumb_travel,
									0,
									1,
								) *
								scroll_travel
							parent.target_scroll.y = parent.scroll.y
						}
					},
				},
			)
		}
		if self.content_size.x > self.last_size.x {
			do_node(
				&{
					is_absolute = true,
					relative_position = {0, 1},
					position = {SCROLLBAR_PADDING, -SCROLLBAR_PADDING - SCROLLBAR_SIZE},
					relative_size = {1, 0},
					size = {-SCROLLBAR_PADDING * 2, SCROLLBAR_SIZE},
					background = tw.NEUTRAL_600,
					foreground = tw.NEUTRAL_800,
					radius = SCROLLBAR_SIZE / 2,
					z_index = 1,
					data = self,
					on_draw = proc(self: ^Node) {
						parent := (^Node)(self.data)
						inner_box := self.box
						length := box_width(inner_box) * parent.size.x / parent.content_size.x
						scroll_travel := max(parent.content_size.x - parent.size.x, 0)
						scroll_time := parent.scroll.x / scroll_travel
						thumb_travel := box_width(inner_box) - length
						thumb_box := Box {
							{inner_box.lo.x + thumb_travel * scroll_time, inner_box.lo.y},
							{0, inner_box.hi.y},
						}
						thumb_box.hi.x = thumb_box.lo.x + length
						kn.add_box(
							thumb_box,
							box_height(thumb_box) / 2,
							paint = self.style.foreground,
						)
						if self.is_active {
							parent.scroll.x =
								clamp(
									(global_ctx.mouse_position.x - inner_box.lo.x) / thumb_travel,
									0,
									1,
								) *
								scroll_travel
							parent.target_scroll.x = parent.scroll.x
						}
					},
				},
			)
		}
		pop_id()
	}

	pop_node()
	if self.parent != nil {
		node_on_child_end(self.parent, self)
	}
}

do_node :: proc(descriptor: ^Node_Descriptor, loc := #caller_location) -> ^Node {
	self := begin_node(descriptor, loc)
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
	assert(depth < 128)
	node_reset_propagated_input(self)
	node_update_this_frame_input(self)
	for node in self.kids {
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
	reserve(&self.kids, 16)
	clear(&self.kids)
	clear(&self.growable_kids)

	self.style.scale = 1

	// Keep alive this frame
	self.is_dead = false

	// Reset some state
	self.content_size = 0
	self.was_changed = false
	self.was_confirmed = false

	// Initialize string reader for text construction
	string_reader: strings.Reader
	reader := strings.to_reader(&string_reader, self.text)
	self.last_selection = self.editor.selection

	// Perform text editing
	// TODO: Implement up/down movement
	if self.enable_edit {
		if self.editor.builder == nil {
			self.editor.builder = &self.builder
			self.editor.undo_text_allocator = context.allocator
			self.editor.set_clipboard = ctx.on_set_clipboard
			self.editor.get_clipboard = ctx.on_get_clipboard
		}
		if !self.is_focused {
			strings.builder_reset(self.editor.builder)
			strings.write_string(self.editor.builder, self.text)
		}
		if self.is_focused {
			cmd: tedit.Command
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
			if len(ctx.runes) > 0 {
				for char, c in ctx.runes {
					tedit.input_runes(&self.editor, {char})
					draw_frames(1)
					self.was_changed = true
				}
			}
			if key_pressed(.Backspace) do cmd = .Delete_Word_Left if control_down else .Backspace
			if key_pressed(.Delete) do cmd = .Delete_Word_Right if control_down else .Delete
			if key_pressed(.Enter) {
				cmd = .New_Line
				if self.is_multiline {
					if control_down {
						self.was_confirmed = true
					}
				} else {
					self.was_confirmed = true
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
			if !self.is_multiline && (cmd in tedit.MULTILINE_COMMANDS) {
				cmd = .None
			}
			if cmd != .None {
				tedit.editor_execute(&self.editor, cmd)
				if cmd in tedit.EDIT_COMMANDS {
					self.was_changed = true
				}
				draw_frames(1)
			}
			reader = strings.to_reader(&string_reader, strings.to_string(self.builder))
		}
	}

	// Assign a default font for safety
	if self.style.font == nil {
		self.style.font = &kn.DEFAULT_FONT
	}

	// Create text layout
	self.text_layout = kn.Selectable_Text {
		text = kn.make_text_with_reader(reader, self.style.font_size, self.style.font^),
	}

	// Include text in content size
	self.content_size = linalg.max(self.content_size, self.text_layout.size, self.last_text_size)

	// If there's no text, just add the font line height to content size
	if kn.text_is_empty(&self.text_layout) && self.enable_edit {
		self.content_size.y = max(
			self.content_size.y,
			self.style.font.line_height * self.style.font_size,
		)
	}

	// Root
	if self.parent == nil {
		append(&ctx.roots, self)
		//
		return
	}

	// Child logic
	append(&self.parent.kids, self)

	if self.grow[int(self.parent.vertical)] && !self.is_absolute {
		append(&self.parent.growable_kids, self)
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
	if global_ctx.snap_to_pixels {
		box_snap(&self.box)
	}
}

node_solve_box_recursively :: proc(self: ^Node, mouse_overlap: bool = true, offset: [2]f32 = {}) {
	node_solve_box(self, offset)

	mouse_overlap := mouse_overlap
	if mouse_overlap {
		mouse_overlap = node_receive_input(self)
	}

	// Update and clamp scroll
	self.target_scroll = linalg.clamp(
		self.target_scroll,
		0,
		linalg.max(self.content_size - self.size, 0),
	)

	previous_scroll := self.scroll
	self.scroll += (self.target_scroll - self.scroll) * rate_per_second(10)
	if max(abs(self.scroll.x - previous_scroll.x), abs(self.scroll.y - previous_scroll.y)) > 0.01 {
		draw_frames(1)
	}

	self.has_clipped_child = false
	for node in self.kids {
		node.z_index += self.z_index
		node_solve_box_recursively(
			node,
			mouse_overlap,
			self.box.lo - self.scroll * f32(i32(!node.is_absolute)),
		)
		node_receive_propagated_input(self, node)
		if box_get_clip(node.box, self.box) != .None {
			self.has_clipped_child = true
		}
	}
}

node_receive_input :: proc(self: ^Node) -> (mouse_overlap: bool) {
	ctx := global_ctx
	if ctx.mouse_position.x >= self.box.lo.x &&
	   ctx.mouse_position.x <= self.box.hi.x &&
	   ctx.mouse_position.y >= self.box.lo.y &&
	   ctx.mouse_position.y <= self.box.hi.y {
		mouse_overlap = true
		if !(ctx.hovered_node != nil && ctx.hovered_node.z_index > self.z_index) {
			ctx.hovered_node = self

			// Check if this node's contents can be scrolled
			if node_is_scrollable(self) {
				ctx.scrollable_node = self
			}
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

	// Receive mouse wheel input
	if ctx.scrollable_node != nil && ctx.scrollable_node.id == self.id {
		self.target_scroll -= ctx.mouse_scroll * 24
	}

	return
}

node_solve_sizes :: proc(self: ^Node) {
	// Axis indices
	i := int(self.vertical)
	j := 1 - i
	// Compute available space
	remaining_space := self.size[i] - self.content_size[i]
	available_span := self.size[j] - self.padding[j] - self.padding[j + 2]
	// As long as there is space remaining and children to grow
	for remaining_space > 0 && len(self.growable_kids) > 0 {
		// Get the smallest size along the layout axis, nodes of this size will be grown first
		smallest := self.growable_kids[0].size[i]
		// Until they reach this size
		second_smallest := f32(math.F32_MAX)
		size_to_add := remaining_space
		for node in self.growable_kids {
			if node.size[i] < smallest {
				second_smallest = smallest
				smallest = node.size[i]
			}
			if node.size[i] > smallest {
				second_smallest = min(second_smallest, node.size[i])
			}
		}
		// Compute the smallest size to add
		size_to_add = min(
			second_smallest - smallest,
			remaining_space / f32(len(self.growable_kids)),
		)
		// Add that amount to every eligable child
		for node, node_index in self.growable_kids {
			if node.size[i] == smallest {
				size_to_add := min(size_to_add, node.max_size[i] - node.size[i])
				if size_to_add <= 0 {
					unordered_remove(&self.growable_kids, node_index)
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

node_is_scrollable :: proc(self: ^Node) -> bool {
	if self.content_size.x <= self.size.x && self.content_size.y <= self.size.y {
		return false
	}
	return true
}


node_draw_recursively :: proc(self: ^Node, depth := 0) {
	assert(depth < 128)
	ctx := global_ctx

	self.last_size = self.size

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
			self.content_align,
		) -
		self.text_layout.size * self.content_align -
		self.scroll

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

	overflow := linalg.max(self.content_size - self.size, 0)

	enable_scissor :=
		self.clip_content && (self.has_clipped_child || max(overflow.x, overflow.y) > 0.1)

	// Compute text selection state if enabled
	if self.enable_selection {
		self.text_layout = kn.make_selectable(
			self.text_layout,
			ctx.mouse_position - self.text_origin,
			self.editor.selection,
		)
		if self.text_layout.contact.valid && self.is_hovered {
			set_cursor(.Text)
		}
		node_update_selection(self)
		cursor_box := text_get_cursor_box(&self.text_layout, self.text_origin)
		left := max(0, self.box.lo.x - cursor_box.lo.x)
		right := max(0, cursor_box.hi.x - self.box.hi.x)
		if max(left, right) > 0 {
			enable_scissor = true
		}
		if self.is_focused && self.editor.selection != self.last_selection {
			self.target_scroll.x += right - left
		}
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
	if enable_scissor {
		kn.push_scissor(kn.make_box(self.box, self.style.radius))
	}

	kn.set_draw_order(int(self.z_index))

	// Draw self
	if ctx.requires_redraw {
		if self.style.shadow_color != {} {
			kn.add_box_shadow(
				self.box,
				self.style.radius[0],
				self.style.shadow_size,
				self.style.shadow_color,
			)
		}
		if self.style.background != {} {
			switch v in self.style.background {
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
		if self.style.foreground != nil && !kn.text_is_empty(&self.text_layout) {
			if self.enable_selection {
				draw_text_highlight(
					&self.text_layout,
					self.text_origin,
					kn.fade(
						global_ctx.selection_background_color,
						0.5 * f32(i32(self.is_focused)),
					),
				)
			}
			if self.enable_selection && self.is_focused {
				draw_text(
					&self.text_layout,
					self.text_origin,
					self.style.foreground,
					global_ctx.selection_foreground_color,
				)
			} else {
				kn.add_text(self.text_layout, self.text_origin, self.style.foreground)
			}
			if self.enable_edit {
				draw_text_cursor(
					&self.text_layout,
					self.text_origin,
					kn.fade(global_ctx.selection_background_color, f32(i32(self.is_focused))),
				)
			}
		}

		if self.on_draw != nil {
			self.on_draw(self)
		}
	}

	// Draw children
	for node in self.kids {
		if box_get_clip(self.box, node.box) == .Full {
			continue
		}
		node_draw_recursively(node, depth + 1)
	}

	if enable_scissor {
		kn.pop_scissor()
	}

	if ctx.requires_redraw {
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
	}

	if is_transformed {
		kn.pop_matrix()
	}

	// Draw debug lines
	if ODIN_DEBUG {
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
				box := self.box
				padding_paint := kn.paint_index_from_option(kn.fade(kn.SKY_BLUE, 0.5))
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
				kn.add_box(self.box, paint = kn.fade(kn.BLUE_VIOLET, 0.5))
			}
		}
	}
}

text_get_cursor_box :: proc(self: ^kn.Selectable_Text, offset: [2]f32) -> Box {
	line_height := self.font.line_height * self.font_scale
	top_left := offset + self.glyphs[self.selection.glyphs[0]].offset
	return {{top_left.x - 1, top_left.y}, {top_left.x + 1, top_left.y + line_height}}
}

draw_text_cursor :: proc(text: ^kn.Selectable_Text, origin: [2]f32, color: kn.Color) {
	if len(text.glyphs) == 0 {
		return
	}
	kn.add_box(text_get_cursor_box(text, origin), paint = color)
}

draw_text :: proc(
	text: ^kn.Selectable_Text,
	origin: [2]f32,
	paint: kn.Paint_Option,
	selected_color: kn.Color,
) {
	ordered_selection := text.selection.glyphs
	if ordered_selection.x > ordered_selection.y {
		ordered_selection = ordered_selection.yx
	}
	default_paint := kn.paint_index_from_option(paint)
	selected_paint := kn.paint_index_from_option(selected_color)
	for &glyph, glyph_index in text.glyphs {
		if glyph.source.lo == glyph.source.hi {
			continue
		}
		kn.add_glyph(
			glyph,
			text.font_scale,
			origin + glyph.offset,
			selected_paint if glyph_index >= ordered_selection[0] && glyph_index < ordered_selection[1] else default_paint,
		)
	}
}

draw_text_highlight :: proc(text: ^kn.Selectable_Text, origin: [2]f32, color: kn.Color) {
	if text.selection.glyphs[0] == text.selection.glyphs[1] {
		return
	}
	line_height := text.font.line_height * text.font_scale
	ordered_selection := text.selection.glyphs
	if ordered_selection[0] > ordered_selection[1] {
		ordered_selection = ordered_selection.yx
	}
	kn.set_paint(color)
	for &line in text.lines {
		highlight_range := [2]int {
			max(ordered_selection[0], line.first_glyph),
			min(ordered_selection[1], line.last_glyph),
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
					f32(i32(ordered_selection[1] > line.last_glyph)),
					line_height,
				},
		}
		kn.add_box(
			box_floored(box),
			3 *
			{
					f32(i32(ordered_selection[0] >= line.first_glyph)),
					0,
					0,
					f32(i32(ordered_selection[1] <= line.last_glyph)),
				},
		)
	}
}

node_update_selection :: proc(self: ^Node) {
	is_separator :: proc(r: rune) -> bool {
		return !unicode.is_alpha(r) && !unicode.is_number(r)
	}

	if self.is_active && self.text_layout.contact.index >= 0 {
		if !self.was_active {
			self.editor.anchor = self.text_layout.contact.index
			if self.click_count == 3 {
				self.editor.selection = {len(self.text), 0}
			} else {
				self.editor.selection = {
					self.text_layout.contact.index,
					self.text_layout.contact.index,
				}
			}
		}
		switch self.click_count {
		case 2:
			allow_precision := self.text_layout.contact.index != self.editor.anchor
			if self.text_layout.contact.index <= self.editor.anchor {
				self.editor.selection[0] =
					self.text_layout.contact.index if (allow_precision && is_separator(rune(self.text[self.text_layout.contact.index]))) else max(0, strings.last_index_proc(self.text[:min(self.text_layout.contact.index, len(self.text))], is_separator) + 1)
				self.editor.selection[1] = strings.index_proc(
					self.text[self.editor.anchor:],
					is_separator,
				)
				if self.editor.selection[1] == -1 {
					self.editor.selection[1] = len(self.text)
				} else {
					self.editor.selection[1] += self.editor.anchor
				}
			} else {
				self.editor.selection[1] = max(
					0,
					strings.last_index_proc(self.text[:self.editor.anchor], is_separator) + 1,
				)
				// `self.text_layout.selection.index - 1` is safe as long as `self.text_layout.selection.index > self.editor.anchor`
				self.editor.selection[0] =
					0 if (allow_precision && is_separator(rune(self.text[self.text_layout.contact.index - 1]))) else strings.index_proc(self.text[self.text_layout.contact.index:], is_separator)
				if self.editor.selection[0] == -1 {
					self.editor.selection[0] = len(self.text)
				} else {
					self.editor.selection[0] += self.text_layout.contact.index
				}
			}
		case 1:
			self.editor.selection[0] = self.text_layout.contact.index
		}
	}
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

//
// SECTION: Builtin UI
//

_BACKGROUND :: tw.NEUTRAL_900
_FOREGROUND :: tw.NEUTRAL_800
_TEXT :: tw.WHITE

Draggable_Node :: struct {
	position:       [2]f32,
	move_offset:    [2]f32,
	is_being_moved: bool,
}

draggable_node_update :: proc(self: ^Draggable_Node, node: ^Node) {
	ctx := global_ctx
	if (node.is_hovered || node.has_hovered_child) && mouse_pressed(.Left) {
		self.is_being_moved = true
		self.move_offset = ctx.mouse_position - self.position
	}
	if mouse_released(.Left) {
		self.is_being_moved = false
	}
	if self.is_being_moved {
		set_cursor(.Dragging)
		self.position = ctx.mouse_position - self.move_offset
	}
}

Settings_Editor :: struct {
	using draggable_node: Draggable_Node,
	ctx:                  ^Context,
}

settings_editor_show :: proc(self: ^Settings_Editor) {
	begin_node(&{position = self.position, data = self, on_animate = proc(self: ^Node) {
				draggable_node_update((^Settings_Editor)(self.data), self)
			}})

	end_node()
}

Inspector :: struct {
	using draggable_node: Draggable_Node,
	shown:                bool,
	selected_id:          Id,
	inspected_id:         Id,
}

inspector_show :: proc(self: ^Inspector) {
	begin_node(
		&{
			position = self.position,
			bounds = get_screen_box(),
			size = {300, 500},
			vertical = true,
			padding = 1,
			style = {stroke_width = 1, stroke = tw.CYAN_800, background = _BACKGROUND},
			z_index = 1,
			disable_inspection = true,
		},
	)
	do_node(
		&{
			text = fmt.tprintf(
				"Inspector\nFPS: %.0f\nFrame time: %v\nCompute time: %v",
				kn.get_fps(),
				global_ctx.frame_duration,
				global_ctx.compute_duration,
			),
			fit = 1,
			padding = 3,
			style = {font_size = 12, background = _FOREGROUND, foreground = _TEXT},
			grow = {true, false},
			max_size = INFINITY,
			data = self,
			on_animate = proc(self: ^Node) {
				draggable_node_update((^Inspector)(self.data), self)
			},
		},
	)
	inspector_reset(&global_ctx.inspector)
	inspector_build_tree(&global_ctx.inspector)
	if self.selected_id != 0 {
		if node, ok := global_ctx.node_by_id[self.selected_id]; ok {
			do_node(
				&{
					size = {0, 200},
					grow = {true, false},
					max_size = INFINITY,
					text = fmt.tprintf("%#v", node),
					clip_content = true,
					show_scrollbars = true,
					style = {font_size = 12, background = _BACKGROUND, foreground = _TEXT},
					enable_selection = true,
				},
			)
		}
	}
	end_node()
}

inspector_build_tree :: proc(self: ^Inspector) {
	begin_node(
		&{
			padding = 4,
			vertical = true,
			max_size = INFINITY,
			grow = true,
			clip_content = true,
			show_scrollbars = true,
		},
	)
	for root in global_ctx.roots {
		if root.disable_inspection {
			continue
		}
		inspector_build_node_widget(self, root)
	}
	end_node()
}

inspector_reset :: proc(self: ^Inspector) {
	self.inspected_id = 0
}

inspector_build_node_widget :: proc(self: ^Inspector, node: ^Node, depth := 0) {
	assert(depth < 128)
	push_id(int(node.id))
	button_node := begin_node(
		&{
			content_align = {0, 0.5},
			spacing = 4,
			grow = {true, false},
			max_size = INFINITY,
			padding = {4, 2, 4, 2},
			fit = {0, 1},
			is_widget = true,
			inherit_state = true,
			data = node,
			on_animate = proc(self: ^Node) {
				node := (^Node)(self.data)
				node_update_transition(self, 0, self.is_toggled, 0.1)
				self.style.background = kn.fade(
					tw.STONE_600,
					f32(i32(self.is_hovered)) * 0.5 + 0.2 * f32(i32(len(node.kids) > 0)),
				)
				if self.is_hovered && self.was_active && !self.is_active {
					self.is_toggled = !self.is_toggled
				}
			},
		},
	)
	do_node(&{size = 14, on_draw = nil if len(node.kids) == 0 else proc(self: ^Node) {
				assert(self.parent != nil)
				kn.add_arrow(box_center(self.box), 5, 2, math.PI * 0.5 * ease.cubic_in_out(self.parent.transitions[0]), kn.WHITE)
			}})
	do_node(
		&{
			text = fmt.tprintf("%x", node.id),
			fit = 1,
			style = {
				font_size = 14,
				foreground = tw.EMERALD_500 if self.selected_id == node.id else kn.fade(tw.EMERALD_50, 0.5 + 0.5 * f32(i32(len(node.kids) > 0))),
			},
		},
	)
	end_node()
	if button_node.is_hovered {
		self.inspected_id = node.id
	}
	if button_node.is_hovered && mouse_pressed(.Right) {
		if self.selected_id == node.id {
			self.selected_id = 0
		} else {
			self.selected_id = node.id
		}
	}
	if button_node.transitions[0] > 0.01 {
		begin_node(
			&{
				padding = {10, 0, 0, 0},
				grow = {true, false},
				max_size = INFINITY,
				fit = {0, ease.quadratic_in_out(button_node.transitions[0])},
				clip_content = true,
				vertical = true,
			},
		)
		for child in node.kids {
			inspector_build_node_widget(self, child, depth + 1)
		}
		end_node()
	}
	pop_id()
}
