package opal

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
import "core:time"
import "vendor:sdl3"

Id :: u32

Box :: kn.Box

Vector2 :: [2]f32

Padding_Config :: struct {
	left, right, top, bottom: f32,
}

//
// **Padding**
//
// **Order:** `{left, top, right, bottom}`
//
Padding :: [4]f32

Dimension_Config :: struct {
	min:  f32,
	max:  f32,
	grow: bool,
}

PADDING_ALL :: proc(amount: f32) -> Padding_Config {
	return Padding_Config{amount, amount, amount, amount}
}

Dimensions :: struct {
	width, height: f32,
}

Size_Config :: struct {
	width, height: Dimension_Config,
}

Axis :: enum {
	Horizontal,
	Vertical,
}

Node_Config :: struct {
	size:       Size_Config,
	kid_gap:    f32,
	span_align: f32,
	vertical:   bool,
	padding:    Padding_Config,
}

Node_Input_Flag :: enum {
	Is_Focused,
}

Root_Node_Config :: struct {
	using base: Node_Config,
	position:   Vector2,
}

//
// **Basic Layout**
//
// One child node after the next with no size limit
//
Basic_Layout :: struct {
	spacing:  f32,
	vertical: bool,
}

//
// **Wrap Layout**
//
// Lays out children like text, wrapping them at `max_span`, extending itself until `max_extent` is reached.
//
Wrap_Layout :: struct {
	spacing:    f32,
	max_extent: f32,
	max_span:   f32,
	align:      f32,
}

//
// **Grid Layout**
//
// A simple grid layout that resolves its own column widths according to row content.  Children are added continuously, and will wrap every `column_count` nodes
//
// **Required fields**
//
// - `column_count`
//
Grid_Layout :: struct {
	column_spacing:   f32,
	row_spacing:      f32,
	column_count:     i32,
	row_count:        i32,
	max_column_width: f32,
}

Layout :: struct {
	min_size: [2]f32,
	max_size: [2]f32,
	padding:  Padding,
	variant:  Layout_Variant,
}

//
// **Unified Layout Variant**
//
// The `nil` state means no layouting will be performed and children will be placed relative to their parent based on their `offset` and `size`.
//
Layout_Variant :: union {
	Basic_Layout,
	Wrap_Layout,
	Grid_Layout,
}

Node :: struct {
	// Node tree references
	parent:             ^Node,
	kids:               [dynamic]^Node,

	// The `box` field represents the final position and size of the node and is only valid after `end()` has been called
	box:                Box,

	// Fields pertaining to the node's own layout within its parent
	position:           [2]f32,
	max_size:           [2]f32,
	size:               [2]f32,
	grow:               [2]bool,

	// Values for the node's children layout
	content_align:      [2]f32,
	content_size:       [2]f32,
	padding:            [4]f32,
	spacing:            f32,
	vertical:           bool,
	growable_kid_count: int,

	// Z index (higher values appear in front of lower ones)
	z_index:            u32,

	// Appearance
	text:               string,
	text_layout:        kn.Text,
	style:              Node_Style,

	// Draw logic override
	on_draw:            proc(self: ^Node),
}

Node_Style :: struct {
	radius:       [4]f32,
	stroke_width: f32,
	stroke_join:  kn.Shape_Outline,
	stroke_paint: kn.Paint_Option,
	fill_paint:   kn.Paint_Option,
}

@(init)
_print_struct_memory_configuration :: proc() {
	fmt.println(size_of(Node), align_of(Node))
}

Context :: struct {
	// Input state
	mouse_position:   Vector2,
	hovered_node:     ^Node,
	focused_node:     ^Node,

	// Contiguous storage of all nodes in the UI
	nodes:            [dynamic]Node,

	// All nodes wihout a parent are stored here
	roots:            [dynamic]^Node,

	// All currently active nodes being processed
	stack:            [dynamic]^Node,

	// The hash stack
	id_stack:         [dynamic]Id,

	// The top-most element of the stack
	current_node:     ^Node,

	// Profiling state
	frame_start_time: time.Time,
	frame_duration:   time.Duration,
}

global_ctx: ^Context

padding_from_parts :: proc(left, right, top, bottom: f32) -> Padding {
	return {left, top, right, bottom}
}

FNV1A64_OFFSET_BASIS :: 0xcbf29ce484222325
FNV1A64_PRIME :: 0x00000100000001B3

fnv64a :: proc(data: []byte, seed: u64) -> u64 {
	h: u64 = seed
	for b in data {
		h = (h ~ u64(b)) * FNV1A64_PRIME
	}
	return h
}

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

context_init :: proc(ctx: ^Context) {
	assert(ctx != nil)
	reserve(&ctx.nodes, 512)
	reserve(&ctx.roots, 64)
	reserve(&ctx.stack, 64)
	reserve(&ctx.id_stack, 64)
}

context_deinit :: proc(ctx: ^Context) {
	assert(ctx != nil)
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

handle_mouse_motion :: proc(x, y: f32) {
	global_ctx.mouse_position = {x, y}
}

handle_text_input :: proc(text: cstring) {

}

handle_key_down :: proc() {

}

begin :: proc() {
	ctx := global_ctx
	ctx.frame_start_time = time.now()

	clear(&ctx.id_stack)
	clear(&ctx.stack)
	clear(&ctx.roots)
	clear(&ctx.nodes)

	push_id(Id(FNV1A32_OFFSET_BASIS))
	ctx.current_node = nil
}

end :: proc() {
	ctx := global_ctx
	ctx.frame_duration = time.since(ctx.frame_start_time)
	for root in ctx.roots {
		root.box = {root.position - root.size / 2, root.position + root.size / 2}

		node_grow_kids_recursively(root)
		node_solve_box_recursively(root)

		kn.set_draw_order(int(root.z_index))
		node_draw_recursively(root)
	}
	if ctx.hovered_node != nil {
		kn.add_box_lines(ctx.hovered_node.box, 1, paint = kn.Green)
	}
	kn.set_draw_order(0)
}

// Attempt to overwrite the currently hovered node respecting z-index
//
// The memory pointed to by `node` must live until the next frame
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
	return {fill_paint = kn.Black, stroke_paint = kn.White, stroke_width = 1}
}

text_node_style :: proc() -> Node_Style {
	return {stroke_width = 1}
}

node_init :: proc(self: ^Node) {
	self.kids = make([dynamic]^Node, 0, 16, allocator = context.temp_allocator)
	if self.text != {} {
		self.text_layout = kn.make_text(self.text, 12)
		self.size = linalg.max(self.size, self.text_layout.size)
	}
}

add_node_as_child_of_current :: proc(node: Node) -> (result: ^Node) {
	ctx := global_ctx
	append(&ctx.nodes, node)
	result = &ctx.nodes[len(ctx.nodes) - 1]
	assert(result != nil)
	result.parent = ctx.current_node
	return
}

begin_node :: proc(node: Node, loc := #caller_location) -> (self: ^Node) {
	ctx := global_ctx
	self = add_node_as_child_of_current(node)
	node_init(self)
	push_node(self)
	if self.parent == nil {
		append(&ctx.roots, self)
		return
	}
	append(&self.parent.kids, self)
	if self.grow[int(self.parent.vertical)] {
		self.parent.growable_kid_count += 1
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
	self.content_size += self.padding.xy + self.padding.zw
	self.content_size[i] += self.spacing * f32(max(len(self.kids) - 1, 0))
	self.size = linalg.max(self.size, self.content_size)
	pop_node()
	if ctx.current_node != nil {
		node_on_child_end(ctx.current_node, self)
	}
}

do_node :: proc(node: Node, loc := #caller_location) {
	begin_node(node, loc)
	end_node()
}

//
// Layout logic
//

node_on_child_end :: proc(self: ^Node, child: ^Node) {
	// Propagate `content_size` up the tree in reverse breadth-first
	if self.vertical {
		self.content_size.y += child.size.y
		self.content_size.x = max(self.content_size.x, child.size.x)
	} else {
		self.content_size.x += child.size.x
		self.content_size.y = max(self.content_size.y, child.size.y)
	}
}

node_solve_box_recursively :: proc(self: ^Node) {
	for node in self.kids {
		node.box.lo = self.box.lo + node.position
		node.box.hi = node.box.lo + node.size
		node_solve_box_recursively(node)
	}
}

node_grow_kids_recursively :: proc(self: ^Node) {
	i := int(self.vertical)
	j := 1 - i

	remaining_space := self.size[i] - self.content_size[i]

	growables := make(
		[dynamic]^Node,
		0,
		self.growable_kid_count,
		allocator = context.temp_allocator,
	)

	for &node in self.kids {
		if node.grow[i] {
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
		available_span := self.size[j] - self.padding[j] - self.padding[j + 2]

		if node.grow[j] {
			node.size[j] = max(node.size[j], available_span)
		}

		node.position[j] =
			self.padding[j] + (available_span - node.size[j]) * self.content_align[j]
		node.position[i] = offset_along_axis + remaining_space * self.content_align[i]
		offset_along_axis += node.size[i] + self.spacing
		node_grow_kids_recursively(node)
	}
}

//
// UI Debugging procedures an constants
//

COLORS := [?]kn.Color{kn.SkyBlue, kn.LightGoldenrodYellow, kn.PaleGreen}

node_draw_recursively :: proc(self: ^Node, depth := 0) {

	ctx := global_ctx
	if ctx.mouse_position.x >= self.box.lo.x &&
	   ctx.mouse_position.x <= self.box.hi.x &&
	   ctx.mouse_position.y >= self.box.lo.y &&
	   ctx.mouse_position.y <= self.box.hi.y {
		try_hover_node(self)
	}

	if self.on_draw != nil {
		self.on_draw(self)
	} else {
		if self.style.fill_paint != nil {
			kn.add_box(self.box, self.style.radius, paint = self.style.fill_paint)
		}
		if !kn.text_is_empty(&self.text_layout) {
			kn.add_text(self.text_layout, self.box.lo, paint = kn.White)
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
	for node in self.kids {
		node_draw_recursively(node, depth + 1)
	}
}

//
// The demo UI
//

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

	init()
	defer deinit()

	MENU_ITEMS := []string {
		"Go to definition",
		"Go to declaration",
		"Find references",
		"Rename symbol",
		"Create macro",
		"Add/remove breakpoint",
		"Set as cold",
	}

	menu_item :: proc(text: string) {
		begin_node(
			{
				size = {},
				max_size = {math.F32_MAX, 30},
				grow = {true, true},
				padding = 4,
				spacing = 20,
				content_align = {0, 0.5},
				style = {fill_paint = kn.DarkSlateGray, radius = 4},
			},
		)
		do_node({text = text, max_size = math.F32_MAX, style = text_node_style()})
		do_node({max_size = math.F32_MAX, grow = true})
		do_node({
			size = {20, 20},
			on_draw = proc(
				self: ^Node,
			) {kn.add_circle((self.box.lo + self.box.hi) / 2, self.size.x / 2, paint = kn.White)},
		})
		end_node()
	}

	loop: for {
		ctx := global_ctx
		sdl3.Delay(10)
		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break loop
			case .MOUSE_MOTION:
				handle_mouse_motion(event.motion.x, event.motion.y)
			case .WINDOW_RESIZED:
				kn.set_size(event.window.data1, event.window.data2)
			case .TEXT_INPUT:
				handle_text_input(event.text.text)
			}
		}

		kn.new_frame()

		begin()
		center := linalg.array_cast(kn.get_size(), f32) / 2
		begin_node(
			{
				position = center,
				padding = 4,
				spacing = 4,
				vertical = true,
				content_align = {1 = 0.5},
				style = {fill_paint = kn.DimGray, radius = 4},
			},
		)
		for item in MENU_ITEMS {
			menu_item(item)
		}
		end_node()
		end()

		kn.set_paint(kn.Yellow)
		kn.add_string(fmt.tprintf("FPS: %.0f", kn.get_fps()), 16, 0)
		kn.add_string(fmt.tprintf("%.0f", ctx.mouse_position), 16, {0, 16})

		kn.set_clear_color(kn.DarkSlateGray)
		kn.present()

		free_all(context.temp_allocator)
	}
}
