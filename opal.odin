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
On_Set_Clipboard_Proc :: #type proc(text: string, data: rawptr)
On_Get_Clipboard_Proc :: #type proc(data: rawptr) -> string
On_Get_Screen_Size_Proc :: #type proc(data: rawptr) -> (width, height: f32)

Mouse_Button :: enum {
	Left,
	Middle,
	Right,
}

Node_Config :: struct {
	padding:         [4]f32,
	text:            string,
	position:        [2]f32,
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
	spacing:         f32,
	self_align:      [2]f32,
	content_align:   [2]f32,
	stroke_width:    f32,
	stroke_type:     Maybe(kn.Shape_Outline),
	radius:          [4]f32,
	font_size:       f32,
	fit:             [2]f32,
	grow:            [2]bool,
	vertical:        bool,
	absolute:        bool,
	wrap:            bool,
	clip:            bool,
	selectable:      bool,
	editable:        bool,
	root:            bool,
	widget:          bool,
	inherit_state:   bool,
	no_inspect:      bool,
	show_scrollbars: bool,
}

node_configure :: proc(self: ^Node, config: Node_Config) {
	self.is_absolute = config.absolute
	self.padding = config.padding
	self.is_widget = config.widget
	self.relative_position = config.relative_pos
	self.spacing = config.spacing
	self.fit = config.fit
	self.grow = config.grow
	self.size = config.size
	self.max_size = config.max_size
	self.content_align = config.content_align
	self.align = config.self_align
	self.position = config.position
	self.vertical = config.vertical
	self.style.shadow_size = config.shadow_size
	self.style.shadow_color = config.shadow_color
	self.style.radius = config.radius
	self.style.stroke_width = config.stroke_width
	self.style.stroke_paint = config.stroke
	self.style.stroke_type = config.stroke_type.? or_else .Inner_Stroke
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
	self.inherit_state = config.inherit_state
	self.disable_inspection = config.no_inspect
	self.show_scrollbars = config.show_scrollbars
	self.data = config.data
}

node_config_clone_of_parent :: proc(config: Node_Config) -> Node_Config {
	config := config
	config.absolute = true
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

	// All nodes invoked between `begin_node` and `end_node`
	kids:               [dynamic]^Node,
	growable_kids:      [dynamic]^Node,

	// A simple kill switch that causes the node to be discarded
	is_dead:            bool,

	// Last frame on which this node was invoked
	frame:              int,

	// Unique identifier
	id:                 Id `fmt:"x"`,

	// The `box` field represents the final position and size of the node and is only valid after `end()` has been called
	box:                Box,

	// A simple way to force a node to remain within certain boundaries
	bounds:             Maybe(Box),

	// The node's local position within its parent; or screen position if its a root
	position:           [2]f32,

	// Added position relative to parent size
	relative_position:  [2]f32,

	// The maximum size the node is allowed to grow to
	max_size:           [2]f32,

	// This is for the node itself to add/subtract from its size on the next frame
	// TODO: Remove this?
	added_size:         [2]f32,

	// The node's actual size, this is subject to change until the end of the frame. The initial value is effectively the node's minimum size
	size:               [2]f32,

	// Added size relative to the parent size
	relative_size:      [2]f32,

	// If the node will be grown to fill available space
	grow:               [2]bool,

	// If the node will grow to acommodate its contents
	fit:                [2]f32,

	// How the node is aligned on its origin if it is absolutely positioned
	align:              [2]f32,

	// How text is aligned within the box
	text_align:         [2]f32,

	// This is known after box is calculated
	text_origin:        [2]f32,

	// Values for the node's children layout
	padding:            [4]f32,

	// How the content will be aligned if there is extra space
	content_align:      [2]f32,

	// This is computed as the minimum space required to fit all children or the node's text content
	content_size:       [2]f32,

	// Spacing added between children
	spacing:            f32,

	// If the node's children are arranged vertically
	vertical:           bool,

	// If true, the node will ignore the normal layout behavior and simply be positioned and sized relative to its parent
	is_absolute:        bool,

	// If text will be wrapped for the next frame
	enable_wrapping:    bool,

	// Marks the node as a clickable widget and will steal mouse events from the native window functionality
	is_widget:          bool,

	// If this is the node with the highest z-index that the mouse overlaps
	was_hovered:        bool,
	is_hovered:         bool,
	has_hovered_child:  bool,

	// Active state (clicked)
	was_active:         bool,
	is_active:          bool,
	has_active_child:   bool,

	// Focused state: by default, a node is focused when clicked and loses focus when another node is clicked
	was_focused:        bool,
	is_focused:         bool,
	has_focused_child:  bool,

	// If this node will treat its children's state as its own
	inherit_state:      bool,

	// Times the node was clicked
	click_count:        u8,

	// Time of last mouse down event over this node
	last_click_time:    time.Time,

	// If overflowing content is clipped
	clip_content:       bool,
	builder:            strings.Builder,

	// Interaction
	enable_selection:   bool,
	enable_edit:        bool,
	is_multiline:       bool,
	was_confirmed:      bool,
	was_changed:        bool,
	is_toggled:         bool,
	disable_inspection: bool,
	show_scrollbars:    bool,

	// Z index (higher values appear in front of lower ones), nodes will inherit their parent's z-index
	z_index:            u32,

	// The timestamp of the node's initialization in the context's arena
	time_created:       time.Time,

	// Text content
	text:               string,
	text_layout:        kn.Selectable_Text `fmt:"-"`,
	last_text_size:     [2]f32,

	// View offset of contents
	scroll:             [2]f32,
	target_scroll:      [2]f32,

	// Current visual parameters
	style:              Node_Style,

	// Text editing state
	select_anchor:      int,
	editor:             tedit.Editor,

	// Universal state transition values for smooth animations
	transitions:        [3]f32,

	//
	// Callbacks for custom look or behavior
	//

	// Called just before the node is drawn, gives the user a chance to modify the node's style or apply animations based on its state
	on_animate:         proc(self: ^Node),

	// Called when the node is first initialized, allocate any additional state here
	on_create:          proc(self: ^Node),

	// Called when the node is discarded, this is to allow the user to clean up any custom state
	on_drop:            proc(self: ^Node),

	// Called after the default drawing behavior
	on_draw:            proc(self: ^Node),

	// Data for use in callbacks
	data:               rawptr,

	// Optional retained data bound to the node for its lifetime. This is for the user to add state to their custom nodes.
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

User_Image :: struct {
	source: Maybe(Box),
	data:   rawptr,
	width:  i32,
	height: i32,
}

Stroke_Type :: kn.Shape_Outline

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
	stroke_paint:     Paint_Option,
	background_paint: Paint_Variant,
	foreground_paint: Paint_Option,
	font:             ^Font,
	shadow_color:     Color,
	stroke_width:     f32,
	font_size:        f32,
	shadow_size:      f32,
}

Context :: struct {
	// Additional frame delay
	frame_interval:             time.Duration,

	// Input state
	screen_size:                Vector2,

	// Current and previous state of mouse position
	mouse_position:             Vector2,
	last_mouse_position:        Vector2,

	// Mouse scroll input
	mouse_scroll:               Vector2,

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

	// Platform-defined callbacks
	on_set_cursor:              On_Set_Cursor_Proc,
	on_set_clipboard:           On_Set_Clipboard_Proc,
	on_get_clipboard:           On_Get_Clipboard_Proc,
	on_get_screen_size:         On_Get_Screen_Size_Proc,

	// User-defined data for callbacks
	callback_data:              rawptr,

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
	interval_start_time:        time.Time,
	interval_duration:          time.Duration,
	compute_start_time:         time.Time,
	compute_duration:           time.Duration,

	// How many frames are queued for drawing
	queued_frames:              int,

	// If the graphics backend should redraw the UI
	requires_redraw:            bool,

	// Debug state
	is_debugging:               bool,
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
	if ctx.frame_start_time != {} {
		ctx.frame_duration = time.since(ctx.frame_start_time)
	}
	if ctx.interval_start_time != {} {
		ctx.interval_duration = time.since(ctx.interval_start_time)
	}
	ctx.interval_start_time = time.now()
	time.sleep(max(0, ctx.frame_interval - ctx.frame_duration))
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

	if key_pressed(.F3) {
		ctx.is_debugging = !ctx.is_debugging
	}

	// Update redraw state
	ctx.requires_redraw = ctx.queued_frames > 0
	ctx.queued_frames = max(0, ctx.queued_frames - 1)
}

//
// Ends UI declaration and constructs the final layout, node boxes are only valid after this is called
//
end :: proc() {
	ctx := global_ctx

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

	if !config.root && self.parent != ctx.current_node {
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
	self.size = linalg.max(self.size, self.content_size * self.fit)
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
	if self.inherit_state {
		self.is_hovered = self.is_hovered | self.has_hovered_child
		self.is_active = self.is_active | self.has_active_child
		self.is_focused = self.is_focused | self.has_focused_child
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
}

node_on_new_frame :: proc(self: ^Node, config: Node_Config) {
	ctx := global_ctx

	reserve(&self.kids, 16)
	clear(&self.kids)
	clear(&self.growable_kids)

	self.style.scale = 1

	self.z_index = 0

	// Configure the node
	node_configure(self, config)

	// TODO: Find a use/place for this!
	// if config.root {
	// 	self.parent = nil
	// }

	// Keep alive this frame
	self.is_dead = false

	// Reset accumulative values
	self.content_size = 0

	// Reset some state
	self.was_changed = false
	self.was_confirmed = false

	// Initialize string reader for text construction
	r: strings.Reader
	reader := strings.to_reader(&r, self.text)

	// Perform text editing
	if self.enable_edit {
		if self.editor.builder == nil {
			self.editor.builder = &self.builder
			self.editor.undo_text_allocator = context.allocator
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
			reader = strings.to_reader(&r, strings.to_string(self.builder))
		}

	}

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

	// TODO: Decide if this is necessary also
	self.size += self.added_size

	// Root
	if self.parent == nil {
		append(&ctx.roots, self)
		//
		return
	}

	// Child logic
	append(&self.parent.kids, self)

	if self.grow[int(self.parent.vertical)] {
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

	node_receive_input(self)
}

node_solve_box_recursively :: proc(self: ^Node, offset: [2]f32 = {}) {
	node_solve_box(self, offset)
	for node in self.kids {
		node.z_index += self.z_index
		node_solve_box_recursively(node, self.box.lo - self.scroll)
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

node_receive_input :: proc(self: ^Node) {
	ctx := global_ctx
	if ctx.mouse_position.x >= self.box.lo.x &&
	   ctx.mouse_position.x <= self.box.hi.x &&
	   ctx.mouse_position.y >= self.box.lo.y &&
	   ctx.mouse_position.y <= self.box.hi.y {
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

	// Update and clamp scroll
	self.target_scroll = linalg.clamp(
		self.target_scroll,
		0,
		linalg.max(self.content_size - self.size, 0),
	)

	previous_scroll := self.scroll
	self.scroll += (self.target_scroll - self.scroll) * rate_per_second(8)
	if max(abs(self.scroll.x - previous_scroll.x), abs(self.scroll.y - previous_scroll.y)) > 0.01 {
		draw_frames(1)
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
	if ctx.requires_redraw {
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
					kn.fade(
						global_ctx.selection_background_color,
						0.5 * f32(i32(self.is_focused)),
					),
				)
			}
			draw_text(
				&self.text_layout,
				self.text_origin,
				self.style.foreground_paint,
				global_ctx.selection_foreground_color,
			)
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

	// kn.add_box(
	// 	self.box,
	// 	self.style.radius,
	// 	kn.fade(kn.RED, max(0, 1 - cast(f32)time.duration_seconds(time.since(self.time_created)))),
	// )

	// Draw children
	for node in self.kids {
		node_draw_recursively(node, depth + 1)
	}

	if self.clip_content {
		kn.pop_scissor()
	}

	if ctx.requires_redraw {
		if self.show_scrollbars {
			SCROLLBAR_SIZE :: 6
			inner_box := box_shrink(self.box, 1)
			if self.content_size.y > self.size.y {
				do_node(
					{
						absolute = true,
						relative_pos = {1, 0},
						position = {-SCROLLBAR_SIZE - 1, 1},
						size = {SCROLLBAR_SIZE, self.size.y - 2},
						bg = tw.NEUTRAL_900,
					},
				)
				// box := Box{{inner_box.hi.x - SCROLLBAR_SIZE, inner_box.lo.y}, inner_box.hi}
				// radius := box_width(box) / 2
				// thumb_size := box_height(box) * self.size.y / self.content_size.y
				// travel := box_height(box) - thumb_size
				// time := self.scroll.y / (self.content_size.y - self.size.y)
				// kn.add_box(box, radius, paint = tw.NEUTRAL_900)
				// thumb_box := Box{{box.lo.x, box.lo.y + travel * time}, {box.hi.x, 0}}
				// thumb_box.hi.y = thumb_box.lo.y + thumb_size
				// kn.add_box(thumb_box, radius, paint = tw.NEUTRAL_700)
			}
		}
		if self.style.stroke_paint != nil {
			kn.add_box_lines(
				self.box,
				self.style.stroke_width,
				self.style.radius,
				paint = self.style.stroke_paint,
				outline = self.style.stroke_type,
			)
		}
	}

	if is_transformed {
		kn.pop_matrix()
	}

	// Draw debug lines
	if ODIN_DEBUG {
		if ctx.is_debugging {
			if self.has_hovered_child {
				kn.add_box_lines(self.box, 1, self.style.radius, paint = kn.LIGHT_GREEN)
			} else if self.is_hovered {
				kn.add_box(self.box, self.style.radius, paint = kn.fade(kn.CADET_BLUE, 0.3))
			}
		}
		if ctx.inspector.inspected_id == self.id {
			if self.parent != nil {
				if box_width(self.box) == 0 {
					kn.add_box(
						{
							{self.parent.box.lo.x, self.box.lo.y},
							{self.parent.box.hi.x, self.box.hi.y},
						},
						paint = kn.fade(kn.GREEN_YELLOW, 0.5),
					)
				}
				if box_height(self.box) == 0 {
					kn.add_box(
						{
							{self.box.lo.x, self.parent.box.lo.y},
							{self.box.hi.x, self.parent.box.hi.y},
						},
						paint = kn.fade(kn.GREEN_YELLOW, 0.5),
					)
				}
			}
			kn.add_box(self.box, paint = kn.fade(kn.BLUE_VIOLET, 0.5))
		}
	}
}

draw_text_cursor :: proc(text: ^kn.Selectable_Text, origin: [2]f32, color: kn.Color) {
	if len(text.glyphs) == 0 {
		return
	}
	line_height := text.font.line_height * text.font_scale
	cursor_origin := origin + text.glyphs[text.selection.glyphs[0]].offset
	kn.add_box(
		{
			{cursor_origin.x - 1, cursor_origin.y},
			{cursor_origin.x + 1, cursor_origin.y + line_height},
		},
		paint = color,
	)
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
	kn.set_paint(paint)
	for &glyph, glyph_index in text.glyphs {
		if glyph.source.lo == glyph.source.hi {
			continue
		}
		if glyph_index == ordered_selection[0] {
			kn.set_paint(selected_color)
		}
		if glyph_index == ordered_selection[1] {
			kn.set_paint(paint)
		}
		kn.add_glyph(glyph, text.font_scale, origin + glyph.offset)
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
			box,
			3 *
			{
					f32(i32(ordered_selection[0] >= line.first_glyph)),
					0,
					0,
					f32(i32(ordered_selection[1] <= line.last_glyph)),
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

Inspector :: struct {
	position:       [2]f32,
	move_offset:    [2]f32,
	is_being_moved: bool,
	selected_id:    Id,
	inspected_id:   Id,
}

INSPECTOR_BACKGROUND :: tw.STONE_900
INSPECTOR_BACKGROUND_ACCENT :: tw.STONE_800

inspector_show :: proc(self: ^Inspector) {
	begin_node({
		position = self.position,
		size = {300, 500},
		vertical = true,
		padding = 1,
		stroke_width = 1,
		stroke = tw.CYAN_800,
		z = 1,
		no_inspect = true,
		data = self,
		bg = INSPECTOR_BACKGROUND,
		on_animate = proc(self: ^Node) {
			inspector := (^Inspector)(self.data)
			if (self.is_hovered || self.has_hovered_child) && mouse_pressed(.Middle) {
				inspector.is_being_moved = true
				inspector.move_offset = global_ctx.mouse_position - self.box.lo
			}
			if mouse_released(.Middle) {
				inspector.is_being_moved = false
			}
			if inspector.is_being_moved {
				set_cursor(.Dragging)
				inspector.position = global_ctx.mouse_position - inspector.move_offset
			}
		},
	})
	do_node(
		{
			text = fmt.tprintf(
				"Inspector\n(%.0f FPS)\n%v",
				kn.get_fps(),
				global_ctx.compute_duration,
			),
			font_size = 12,
			fit = 1,
			padding = 3,
			fg = tw.CYAN_50,
			grow = {true, false},
			max_size = INFINITY,
			content_align = 0.5,
		},
	)
	inspector_reset(&global_ctx.inspector)
	inspector_build_tree(&global_ctx.inspector)
	if self.selected_id != 0 {
		if node, ok := global_ctx.node_by_id[self.selected_id]; ok {
			do_node(
				{
					size = {0, 200},
					grow = {true, false},
					max_size = INFINITY,
					text = fmt.tprintf("%#v", node),
					font_size = 12,
					clip = true,
					show_scrollbars = true,
					bg = tw.NEUTRAL_950,
					stroke = tw.NEUTRAL_500,
					stroke_width = 1,
					fg = tw.GRAY_50,
				},
			)
		}
	}
	end_node()
}

inspector_build_tree :: proc(self: ^Inspector) {
	begin_node(
		{
			padding = 4,
			vertical = true,
			max_size = INFINITY,
			grow = true,
			clip = true,
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
	button_node := begin_node({
		content_align = {0, 0.5},
		spacing = 4,
		grow = {true, false},
		max_size = INFINITY,
		padding = {4, 2, 4, 2},
		fit = {0, 1},
		widget = true,
		inherit_state = true,
		data = node,
		on_animate = proc(self: ^Node) {
			node := (^Node)(self.data)
			self.style.background_paint = kn.fade(
				tw.STONE_600,
				f32(i32(self.is_hovered)) * 0.5 + 0.2 * f32(i32(len(node.kids) > 0)),
			)
			if self.is_hovered && self.was_active && !self.is_active {
				self.is_toggled = !self.is_toggled
			}
			node_update_transition(self, 0, self.is_toggled, 0.1)
		},
	})
	do_node({size = 14, on_draw = nil if len(node.kids) == 0 else proc(self: ^Node) {
			assert(self.parent != nil)
			kn.add_arrow(box_center(self.box), 5, 2, math.PI * 0.5 * ease.cubic_in_out(self.parent.transitions[0]), kn.WHITE)
		}})
	do_node(
		{
			text = fmt.tprintf("%x", node.id),
			font_size = 14,
			fit = 1,
			fg = tw.EMERALD_500 if self.selected_id == node.id else kn.fade(tw.EMERALD_50, 0.5 + 0.5 * f32(i32(len(node.kids) > 0))),
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
			{
				padding = {10, 0, 0, 0},
				grow = {true, false},
				max_size = INFINITY,
				fit = {0, ease.quadratic_in_out(button_node.transitions[0])},
				clip = true,
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

