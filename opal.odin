package opal

//
// The following are features and optimizations that could be necessary depending on what features I deem a priority in the future. Only to be implemented if absolutely necessary and if they don't compromise the system's simplicity and low-level control, or add pointless overhead.
// 	- Add an 'inline' layout mode to, well, layout children inline along any axis allowing for wrapping. Text layout and such could then be migrated to opal entirely. Adding nodes in between text is already possible, but there is no support for wrapping such nodes.
// 	- Abstract away the functional components of a Node (Descriptor, Retained_State, Transient_State) to allow for transient nodes wihout hashed ids or interaction logic. Flex layouts need only a descriptor and some transient state, while inline layouts need additional retained state for caching their size. Ids will become retained state as they are only required by interactive nodes.
//
// TODO:
// 	[ ] Change from `parent` and `owner` to a more explicit `layout_parent` and `state_parent`
//  [ ] Add inner shadows (to katana)
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

Node_Result :: Maybe(^Node)

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
// TODO: Say something here
//
Node_Tier :: enum {
	Inert,
	Interactive,
	Editable,
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

	// Relative placement
	node_relative_placement: Maybe(Node_Relative_Placement),

	//
	exact_position:          Maybe([2]f32),

	// Added position relative to parent size
	relative_position:       [2]f32,

	// The node's actual size, this is subject to change until the end of the frame. The initial value is effectively the node's minimum size
	min_size:                [2]f32,

	// The maximum size the node is allowed to grow to
	max_size:                [2]f32,

	// Added size relative to the parent size
	relative_size:           [2]f32,

	// If the node will be grown to fill available space
	grow:                    [2]bool,

	// If the node will grow to acommodate its contents
	fit:                     [2]f32,

	// Values for the node's children layout
	padding:                 [4]f32,

	// How the content will be aligned if there is extra space
	content_align:           [2]f32,

	// Spacing added between children
	gap:                     f32,

	//
	justify_between:         bool,

	// If this node will inherit the combined state of its children
	inherit_state:           bool,

	// If the node's children are arranged vertically
	vertical:                bool,

	// TODO: Try remove this. It complicates the layout code and its purpose can be achieved by creating a new root
	// If true, the node will ignore the normal layout behavior and simply be positioned and sized relative to its parent
	// is_absolute:             bool,

	// Wraps contents
	wrapped:                 bool,

	// Prevents the node from being adopted and instead adds it as a new root.
	is_root:                 bool,

	// If overflowing content is clipped
	clip_content:            bool,

	// If text content can be selected
	enable_selection:        bool,

	// If text content can be edited
	enable_edit:             bool,

	// Disallows inspection in the debug inspector
	disable_inspection:      bool,

	// Show/hide scrollbars when content overflows
	show_scrollbars:         bool,

	// Forces equal width and height when fitting to content size
	square_fit:              bool,

	//
	interactive:             bool,

	// An optional node that will behave as if it were this node's parent, when it doesn't in fact have one. Input state will be transfered to the owner.
	owner:                   ^Node,

	// Called after the default drawing behavior
	on_draw:                 proc(self: ^Node),

	// Data for use in callbacks, this data should live from the invocation of this node until the UI is ended.
	data:                    rawptr,
}

Glyph :: struct {
	using glyph:    kn.Font_Glyph,
	offset:         [2]f32,
	is_placeholder: bool,
}

//
// Generic UI nodes, everything is a made out of these
//
Node :: struct {
	using descriptor:        Node_Descriptor,

	// Node tree references
	parent:                  ^Node,

	// All nodes invoked between `begin_node` and `end_node`
	children:                [dynamic]^Node `fmt:"-"`,

	// A simple kill switch that causes the node to be discarded
	is_dead:                 bool,

	//
	dirty:                   bool,

	// Last frame on which this node was invoked
	frame:                   int,

	// Unique identifier
	id:                      Id `fmt:"x"`,

	// The node's local position within its parent; or screen position if its a root
	position:                [2]f32,

	//
	size:                    [2]f32,

	//
	cached_size:             [2]f32,

	//
	last_size:               [2]f32,

	// The content size minus the last calculated size
	overflow:                [2]f32,

	// This is computed as the minimum space required to fit all children or the node's text content
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

	// String builder for content editing
	builder:                 strings.Builder `fmt:"-"`,

	// Interaction
	is_toggled:              bool,

	// The timestamp of the node's initialization in the context's arena
	time_created:            time.Time,

	// Text content
	glyphs:                  []Glyph `fmt:"-"`,

	// View offset of contents
	scroll:                  [2]f32,
	target_scroll:           [2]f32,

	// Needs scissor
	has_clipped_child:       bool,
	is_clipped:              bool,

	// Text editing state
	editor:                  tedit.Editor,
	last_selection:          [2]int,

	// Universal state transition values for smooth animations
	transitions:             [3]f32,
}

Rune :: struct {
	box:     Box,
	index:   int,
	code:    rune,
	node_id: Id,
}

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

//
// An abstraction that manages multiple nodes with text content.
//
// Any interactive node with text will be included in only the top text on the stack at the time.
//
Text :: struct {
	builder: strings.Builder,
	editor:  tedit.Editor,
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

	// The mouse offset from the clicked node
	node_click_offset:         Vector2,

	// Current and previous states of mouse buttons
	mouse_button_down:         [Mouse_Button]bool,
	mouse_button_was_down:     [Mouse_Button]bool,

	// Current and previous state of keyboard
	key_down:                  [Keyboard_Key]bool,
	key_was_down:              [Keyboard_Key]bool,

	// If a widget is hovered which would prevent native window interaction
	widget_hovered:            bool,

	// Which node will receive scroll input
	scrollable_node:           ^Node,

	// Transient pointers to interacted nodes
	hovered_node:              ^Node,
	focused_node:              ^Node,
	active_node:               ^Node,

	// Ids of interacted nodes
	hovered_id:                Id,
	focused_id:                Id,
	active_id:                 Id,

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
	nodes:                     [4096]Maybe(Node),

	// All nodes wihout a parent are stored here for layout solving.
	roots:                     [dynamic]^Node,

	// The stack of nodes being declared. May contain multiple roots, as its only a way of keeping track of the nodes currently being invoked.
	node_stack:                [dynamic]^Node,

	// The hash stack
	id_stack:                  [dynamic]Id,

	// Runes
	// runes:                     [dynamic]Rune,
	//
	text_stack:                [dynamic]^Text,
	text_map:                  map[Id]^Text,
	text_array:                [dynamic]Text,

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

begin_text :: proc(loc := #caller_location) {
	ctx := global_ctx
	id := hash_loc(loc)
	text, ok := ctx.text_map[id]
	if !ok {
		append(&ctx.text_array, Text{})
		text = &ctx.text_array[len(ctx.text_array) - 1]
	}
	append(&ctx.text_stack, text)
}

end_text :: proc() -> Maybe(^Text) {
	ctx := global_ctx
	pop(&ctx.text_stack)
	return nil
}

current_text :: proc() -> (text: ^Text, ok: bool) {
	ctx := global_ctx
	if len(ctx.text_array) == 0 {
		return
	}
	return &ctx.text_array[len(ctx.text_array) - 1], true
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
	ctx.active = ctx.queued_frames > 0
	if ctx.active {
		ctx.last_draw_time = time.now()
	}
	ctx.queued_frames = max(0, ctx.queued_frames - 1)

	// Update durations
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

	ctx.frame_start_time = time.now()

	//
	// Reset UI state
	//
	clear(&ctx.id_stack)
	push_id(Id(FNV1A32_OFFSET_BASIS))
	ctx.frame += 1
	ctx.call_index = 0
	ctx.widget_hovered = false
	ctx.current_node = nil

	// Check if this frame received input
	if ctx.active {
		// Resolve input state
		ctx.focused_node = nil
		ctx.active_node = nil
		ctx.scrollable_node = nil
		ctx.hovered_node = nil
		for root in ctx.roots {
			node_receive_input_recursive(root)
		}
	}

	if ctx.hovered_node != nil {
		ctx.hovered_id = ctx.hovered_node.id
		if ctx.hovered_node.interactive {
			ctx.widget_hovered = true
		}
	} else {
		ctx.hovered_id = 0
	}

	if mouse_pressed(.Left) {
		if ctx.hovered_node != nil {
			ctx.active_node = ctx.hovered_node
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
	}

	if ctx.active_node != nil {
		ctx.active_id = ctx.active_node.id
	} else if mouse_released(.Left) {
		ctx.active_id = 0
	}

	// Receive mouse wheel input
	if ctx.scrollable_node != nil {
		ctx.scrollable_node.target_scroll -= ctx.mouse_scroll * 24
	}

	// Propagate input
	// TODO: Can this be done only when necessary?
	for root in ctx.roots {
		node_propagate_input_recursively(root)
	}

	//
	// Reset the node tree for reconstruction
	//
	for id, node in ctx.node_by_id {
		if node.is_dead {
			delete_key(&ctx.node_by_id, node.id)
			// if node.on_drop != nil {
			// 	node.on_drop(node)
			// }
			node_destroy(node)
			(^Maybe(Node))(node)^ = nil
		} else {
			node.is_dead = true
			node.dirty = false
			if id == ctx.inspector.selected_id {
				ctx.inspector.inspected_node = node^
			}
		}
	}

	clear(&ctx.node_stack)
	clear(&ctx.roots)
}

end :: proc() {
	ctx := global_ctx

	ctx.frame_duration = time.since(ctx.frame_start_time)

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
	ctx_solve_positions_and_draw(ctx)

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
	for root in self.roots {
		if !root.dirty {
			continue
		}
		if node_solve_sizes_and_wrap_recursive(root) {
			node_solve_sizes_recursive(root)
		}
	}
}

ctx_solve_positions_and_draw :: proc(self: ^Context) {
	for root in self.roots {
		if placement, ok := root.node_relative_placement.?; ok {
			root.position =
				placement.node.box.lo +
				placement.node.size * placement.relative_offset +
				placement.exact_offset
		}
		node_solve_box_recursively(root, root.dirty)
	}

	for root in self.roots {
		node_draw_recursive(root)
	}
}

node_update_scroll :: proc(self: ^Node) {
	// Update and clamp scroll
	self.target_scroll = linalg.clamp(self.target_scroll, 0, self.overflow)
	previous_scroll := self.scroll
	self.scroll += (self.target_scroll - self.scroll) * rate_per_second(10)
	if max(abs(self.scroll.x - previous_scroll.x), abs(self.scroll.y - previous_scroll.y)) > 0.01 {
		draw_frames(1)
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
	if ctx.hovered_node != nil && ctx.hovered_node.z_index > node.z_index {
		return
	}
	ctx.hovered_node = node
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
					id           = id,
					time_created = time.now(),
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

		if position, ok := self.exact_position.?; ok {
			self.position = position
		}
		self.size = self.min_size

		if !self.is_root {
			self.parent = ctx.current_node
			assert(self != self.parent)
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

	if self.size != self.last_size {
		self.last_size = self.size
		self.dirty = true
	}

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
					is_root = true,
					owner = self,
					relative_position = {1, 0},
					exact_position = [2]f32 {
						-SCROLLBAR_SIZE - SCROLLBAR_PADDING,
						SCROLLBAR_PADDING,
					},
					relative_size = {0, 1},
					min_size = {SCROLLBAR_SIZE, SCROLLBAR_PADDING * -2 - corner_space},
					interactive = true,
					style = scrollbar_style,
					on_draw = scrollbar_on_draw,
					vertical = true,
				},
			).?
			added_size := SCROLLBAR_SIZE * 2 * node.transitions[1]
			node.size.x += added_size
			node.position.x -= added_size
			node.radius = node.size.x / 2
		}
		if self.overflow.x > 0 {
			node := add_node(
				&{
					is_root = true,
					owner = self,
					node_relative_placement = Node_Relative_Placement {
						node = self,
						relative_offset = {0, 1},
						exact_offset = {SCROLLBAR_PADDING, -SCROLLBAR_PADDING - SCROLLBAR_SIZE},
					},
					relative_position = {0, 1},
					exact_position = [2]f32 {
						SCROLLBAR_PADDING,
						-SCROLLBAR_SIZE - SCROLLBAR_PADDING,
					},
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
	if self.parent != nil {
		node_on_child_end(self.parent, self)
	}
}

add_node :: proc(descriptor: ^Node_Descriptor, loc := #caller_location) -> Node_Result {
	self := begin_node(descriptor, loc)
	end_node()
	return self
}

scrollbar_on_draw :: proc(self: ^Node) {
	assert(self.owner != nil)

	node_update_transition(self, 0, true, 0.1)
	node_update_transition(self, 1, self.is_hovered || self.is_active, 0.1)

	i := int(self.vertical)
	j := 1 - i

	inner_box := Box{self.box.lo + self.padding.xy, self.box.hi - self.padding.zw}
	length := max(
		(inner_box.hi[i] - inner_box.lo[i]) * self.owner.size[i] / self.owner.content_size[i],
		30,
	)

	scroll_travel := max(self.owner.content_size[i] - self.owner.size[i], 0)
	scroll_time := self.owner.scroll[i] / scroll_travel

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

		self.owner.scroll[i] =
			clamp(
				(global_ctx.mouse_position[i] -
					(inner_box.lo[i] + global_ctx.node_click_offset[i])) /
				thumb_travel,
				0,
				1,
			) *
			scroll_travel

		self.owner.target_scroll[i] = self.owner.scroll[i]
	}
}

//
// Node logic
//

focus_node :: proc(id: Id) {
	global_ctx.focused_id = id
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
	self.is_dead = false

	// Reset some state
	self.content_size = 0

	// Initialize string reader for text construction
	string_reader: strings.Reader
	reader: Maybe(io.Reader)
	if len(self.text) > 0 {
		reader = strings.to_reader(&string_reader, self.text)
	}
	self.last_selection = self.editor.selection

	// Perform text editing
	// TODO: Implement up/down movement
	/*
	if self.enable_edit {
		if self.editor.builder == nil {
			self.editor.builder = &self.builder
			self.editor.undo_text_allocator = context.allocator
			self.editor.set_clipboard = ctx.on_set_clipboard
			self.editor.get_clipboard = ctx.on_get_clipboard
		}
		if self.is_focused != self.was_focused {
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
			if len(ctx.text_input) > 0 {
				for char, c in ctx.text_input {
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
	*/

	// Assign a default font for safety
	if self.style.font == nil {
		self.style.font = &kn.DEFAULT_FONT
		assert(self.style.font != nil)
	}

	// Create text layout
	if reader, ok := reader.?; ok {
		width: f32
		glyphs := make([dynamic]Glyph, allocator = context.temp_allocator)
		for {
			char, size, err := io.read_rune(reader)
			if err == .EOF {
				break
			}
			if char == '\t' {
				append(&glyphs, Glyph{offset = {width, 0}})
				width += self.font.space_advance * self.font_size * 2
			} else if glyph, ok := kn.get_font_glyph(self.font, char); ok {
				append(&glyphs, Glyph{glyph = glyph, offset = {width, 0}})
				width += glyph.advance * self.font_size
			} else {
				for char in fmt.tprintf("<0x%x>", char) {
					if glyph, ok := kn.get_font_glyph(self.font, char); ok {
						append(
							&glyphs,
							Glyph{glyph = glyph, offset = {width, 0}, is_placeholder = true},
						)
						width += glyph.advance * self.font_size
					}
				}
			}
		}
		width += f32(len(glyphs) - 1) * self.gap
		self.glyphs = glyphs[:]
		// Include text in content size
		self.content_size = linalg.max(
			self.content_size,
			[2]f32{width, self.font.line_height * self.font_size},
		)
	} else if self.enable_edit {
		// Simulate text height
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
	if global_ctx.snap_to_pixels {
		box_snap(&self.box)
	}
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
	}
	if self.is_clipped {
		return
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

	self.overflow = linalg.max(self.content_size - self.size, 0)

	needs_resolve = node_solve_sizes(self)

	if self.wrapped {
		for child in self.children {
			needs_resolve |= node_solve_sizes_and_wrap_recursive(child, depth + 1)
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
		}
	}
	self.overflow = linalg.max(self.content_size - self.size, 0)

	return
}

//
// Second pass
//
node_solve_sizes_recursive :: proc(self: ^Node, depth := 1) {
	assert(depth < MAX_TREE_DEPTH)

	if self.wrapped {
		return
	}

	node_solve_sizes_in_range(self, 0, len(self.children), node_get_content_span(self), 0)
	self.overflow = linalg.max(self.content_size - self.size, 0)

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

//
// Determine node positions
//
// node_solve_positions_recursive :: proc(self: ^Node, depth := 1) {
// 	assert(depth < MAX_TREE_DEPTH)
// }

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

	ctx := global_ctx

	if self.is_clipped {
		return
	}

	when ODIN_DEBUG {
		ctx.drawn_nodes += 1
	}

	// Compute text position
	text_origin :=
		linalg.lerp(
			self.box.lo + self.padding.xy,
			self.box.hi - self.padding.zw,
			self.content_align,
		) -
		self.scroll

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

	if ctx.active && self.shadow_color != {} {
		kn.add_box_shadow(self.box, self.radius[0], self.shadow_size, self.shadow_color)
	}

	// Apply clipping
	if enable_scissor {
		kn.push_scissor(kn.make_box(self.box, self.style.radius))
	}

	// Draw self
	if ctx.active {
		if self.background != {} {
			kn.add_box(
				self.box,
				self.style.radius,
				paint = node_convert_paint_variant(self, self.background),
			)
		}
		if self.style.foreground != nil {
			default_paint := kn.paint_index_from_option(self.foreground)
			placeholder_paint := kn.paint_index_from_option(Color{255, 50, 50, 128})
			text_origin := self.box.lo + self.padding.xy
			for &glyph in self.glyphs {
				kn.add_glyph(
					glyph,
					self.font_size,
					text_origin + glyph.offset,
					placeholder_paint if glyph.is_placeholder else default_paint,
				)
			}
			if self.enable_edit && self.is_focused {
				line_height := self.font.line_height * self.font_size
				top_left := text_origin + self.glyphs[self.editor.selection[0]].offset
				kn.add_box(
					{{top_left.x - 1, top_left.y}, {top_left.x + 1, top_left.y + line_height}},
					paint = ctx.colors[.Selection_Background],
				)
			}
		}

		if self.on_draw != nil {
			self.on_draw(self)
		}
	}

	// Draw children
	for node in self.children {
		node_draw_recursive(node, z_index, depth + 1)
	}

	if enable_scissor {
		kn.pop_scissor()
	}

	if ctx.active {
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

node_get_padded_box :: proc(self: ^Node) -> Box {
	return Box{self.box.lo + self.padding.xy, self.box.hi - self.padding.zw}
}

text_get_cursor_box :: proc(self: ^kn.Selectable_Text, offset: [2]f32) -> Box {
	if len(self.glyphs) == 0 {
		return {}
	}
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
		if highlight_range.x >= highlight_range.y {
			continue
		}
		assert(
			text.glyphs[highlight_range[0]].offset.y == text.glyphs[highlight_range[1]].offset.y,
		)
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

// node_update_selection :: proc(self: ^Node) {
// 	is_separator :: proc(r: rune) -> bool {
// 		return !unicode.is_alpha(r) && !unicode.is_number(r)
// 	}


// 	for glyph in self.glyphs {

// 	}

// 	if self.is_active && self.text_layout.contact.index >= 0 {
// 		if !self.was_active {
// 			self.editor.anchor = self.text_layout.contact.index
// 			if self.click_count == 3 {
// 				self.editor.selection = {len(self.text), 0}
// 			} else {
// 				self.editor.selection = {
// 					self.text_layout.contact.index,
// 					self.text_layout.contact.index,
// 				}
// 			}
// 		}
// 		switch self.click_count {
// 		case 2:
// 			allow_precision := self.text_layout.contact.index != self.editor.anchor
// 			if self.text_layout.contact.index <= self.editor.anchor {
// 				self.editor.selection[0] =
// 					self.text_layout.contact.index if (allow_precision && is_separator(rune(self.text[self.text_layout.contact.index]))) else max(0, strings.last_index_proc(self.text[:min(self.text_layout.contact.index, len(self.text))], is_separator) + 1)
// 				self.editor.selection[1] = strings.index_proc(
// 					self.text[self.editor.anchor:],
// 					is_separator,
// 				)
// 				if self.editor.selection[1] == -1 {
// 					self.editor.selection[1] = len(self.text)
// 				} else {
// 					self.editor.selection[1] += self.editor.anchor
// 				}
// 			} else {
// 				self.editor.selection[1] = max(
// 					0,
// 					strings.last_index_proc(self.text[:self.editor.anchor], is_separator) + 1,
// 				)
// 				// `self.text_layout.selection.index - 1` is safe as long as `self.text_layout.selection.index > self.editor.anchor`
// 				self.editor.selection[0] =
// 					0 if (allow_precision && is_separator(rune(self.text[self.text_layout.contact.index - 1]))) else strings.index_proc(self.text[self.text_layout.contact.index:], is_separator)
// 				if self.editor.selection[0] == -1 {
// 					self.editor.selection[0] = len(self.text)
// 				} else {
// 					self.editor.selection[0] += self.text_layout.contact.index
// 				}
// 			}
// 		case 1:
// 			self.editor.selection[0] = self.text_layout.contact.index
// 		}
// 	}
// }

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

Panel_State :: enum {
	None,
	Moving,
	Resizing,
}

Resize :: enum {
	None,
	Near,
	Far,
}

Panel :: struct {
	position:    [2]f32,
	size:        [2]f32,
	min_size:    [2]f32,
	resize_mode: [2]Resize,
	anchor:      [2]f32,
	state:       Panel_State,
	cursor:      Cursor,
}

panel_update :: proc(self: ^Panel, base_node, grab_node: ^Node) {
	ctx := global_ctx

	switch self.state {
	case .None:
		// Resizing
		if base_node != nil {
			if base_node.is_hovered || base_node.has_hovered_child {
				size :: 8
				left_box := Box{base_node.box.lo, {base_node.box.lo.x + size, base_node.box.hi.y}}
				top_box := Box{base_node.box.lo, {base_node.box.hi.x, base_node.box.lo.y + size}}
				right_box := Box {
					{base_node.box.hi.x - size, base_node.box.lo.y},
					{base_node.box.hi.x, base_node.box.hi.y},
				}
				bottom_box := Box {
					{base_node.box.lo.x, base_node.box.hi.y - size},
					{base_node.box.hi.x, base_node.box.hi.y},
				}
				over_left := point_in_box(ctx.mouse_position, left_box)
				over_right := point_in_box(ctx.mouse_position, right_box)
				over_top := point_in_box(ctx.mouse_position, top_box)
				over_bottom := point_in_box(ctx.mouse_position, bottom_box)
				over_left_or_right := over_left || over_right
				over_top_or_bottom := over_top || over_bottom
				self.cursor = .Normal
				if over_left_or_right && over_top_or_bottom {
					if (over_left && over_top) || (over_right && over_bottom) {
						self.cursor = .Resize_NWSE
					} else if (over_right && over_top) || (over_left && over_bottom) {
						self.cursor = .Resize_NESW
					}
				} else {
					if over_left_or_right {
						self.cursor = .Resize_EW
					} else if over_top_or_bottom {
						self.cursor = .Resize_NS
					}
				}
				set_cursor(self.cursor)
				if mouse_pressed(.Left) {
					if over_left_or_right || over_top_or_bottom {
						self.state = .Resizing
						self.resize_mode = {
							Resize(i32(over_left_or_right) + i32(over_right)),
							Resize(i32(over_top_or_bottom) + i32(over_bottom)),
						}
						self.anchor = base_node.box.hi
					}
				}
			}
		}
		if self.state == .None &&
		   (grab_node.is_hovered || grab_node.has_hovered_child) &&
		   mouse_pressed(.Left) {
			self.state = .Moving
			self.anchor = ctx.mouse_position - self.position
		}
	case .Moving:
		if self.state == .Moving {
			set_cursor(.Move)
			self.position = ctx.mouse_position - self.anchor
		}
	case .Resizing:
		for i in 0 ..= 1 {
			switch self.resize_mode[i] {
			case .None:
			case .Near:
				self.position[i] = min(ctx.mouse_position[i], self.anchor[i] - self.min_size[i])
				self.size[i] = self.anchor[i] - self.position[i]
			case .Far:
				self.size[i] = ctx.mouse_position[i] - self.position[i]
			}
		}
		set_cursor(self.cursor)
	}

	if mouse_released(.Left) {
		self.state = .None
	}
}

Inspector :: struct {
	using panel:    Panel,
	shown:          bool,
	selected_id:    Id,
	inspected_id:   Id,
	inspected_node: Node,
}

inspector_show :: proc(self: ^Inspector) {
	self.min_size = {400, 500}
	self.size = linalg.max(self.size, self.min_size)
	base_node := begin_node(
		&{
			exact_position = self.position,
			min_size = self.size,
			bounds = get_screen_box(),
			vertical = true,
			padding = 1,
			shadow_size = 10,
			shadow_color = tw.BLACK,
			stroke_width = 2,
			stroke = tw.CYAN_800,
			background = _BACKGROUND,
			z_index = 1,
			disable_inspection = true,
			radius = 7,
		},
	).?
	total_nodes := len(global_ctx.node_by_id)
	handle_node := begin_node(
		&{
			fit = 1,
			padding = 5,
			style = {background = _FOREGROUND},
			grow = {true, false},
			max_size = INFINITY,
			interactive = true,
			vertical = true,
		},
	).?
	{
		desc := Node_Descriptor {
			fit        = 1,
			font_size  = 12,
			foreground = _TEXT,
		}
		desc.text = fmt.tprintf("FPS: %.0f", kn.get_fps())
		add_node(&desc)
		desc.text = fmt.tprintf("Frame time: %v", global_ctx.frame_duration)
		add_node(&desc)
		desc.text = fmt.tprintf("Interval time: %v", global_ctx.interval_duration)
		add_node(&desc)
		desc.text = fmt.tprintf("Compute time: %v", global_ctx.compute_duration)
		add_node(&desc)
		desc.text = fmt.tprintf(
			"%i/%i nodes drawn",
			global_ctx.drawn_nodes,
			len(global_ctx.node_by_id),
		)
		add_node(&desc)
	}
	end_node()
	panel_update(self, base_node, handle_node)
	inspector_reset(&global_ctx.inspector)
	inspector_build_tree(&global_ctx.inspector)
	if self.selected_id != 0 {
		begin_node(
			&{
				min_size = {0, 200},
				grow = {true, false},
				padding = 4,
				max_size = INFINITY,
				clip_content = true,
				show_scrollbars = true,
				style = {background = tw.NEUTRAL_950},
				interactive = true,
				vertical = true,
			},
		)
		lines := strings.split(
			fmt.tprintf("%#v", self.inspected_node),
			"\n",
			allocator = context.temp_allocator,
		)
		for line, i in lines {
			push_id(int(i))
			add_node(&{foreground = _TEXT, font_size = 12, fit = 1, text = line})
			pop_id()
		}
		end_node()
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
			interactive = true,
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
	assert(depth < MAX_TREE_DEPTH)
	push_id(int(node.id))
	button_node := begin_node(
		&{
			content_align = {0, 0.5},
			gap = 4,
			grow = {true, false},
			max_size = INFINITY,
			padding = {4, 2, 4, 2},
			fit = {0, 1},
			interactive = true,
			inherit_state = true,
		},
	).?
	add_node(&{min_size = 14, on_draw = nil if len(node.children) == 0 else proc(self: ^Node) {
				assert(self.parent != nil)
				kn.add_arrow(box_center(self.box), 5, 2, math.PI * 0.5 * ease.cubic_in_out(self.parent.transitions[0]), kn.WHITE)
			}})
	add_node(
		&{
			text = node.text if len(node.text) > 0 else fmt.tprintf("%x", node.id),
			fit = 1,
			style = {
				font_size = 14,
				foreground = tw.EMERALD_500 if self.selected_id == node.id else kn.fade(tw.EMERALD_50, 0.5 + 0.5 * f32(i32(len(node.children) > 0))),
			},
		},
	)
	end_node()
	if button_node.is_hovered {
		self.inspected_id = node.id
		if button_node.was_active && !button_node.is_active {
			button_node.is_toggled = !button_node.is_toggled
		}
	}
	if button_node.is_hovered && mouse_pressed(.Right) {
		if self.selected_id == node.id {
			self.selected_id = 0
		} else {
			self.selected_id = node.id
		}
	}
	button_node.background = kn.fade(
		tw.STONE_600,
		f32(i32(button_node.is_hovered)) * 0.5 + 0.2 * f32(i32(len(node.children) > 0)),
	)
	node_update_transition(button_node, 0, button_node.is_toggled, 0.1)
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
		for child in node.children {
			inspector_build_node_widget(self, child, depth + 1)
		}
		end_node()
	}
	pop_id()
}
