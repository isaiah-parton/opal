package opal

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:reflect"
import "core:slice"
import "core:time"
import kn "local:katana"
import "vendor:sdl2"

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
	box:                Box,
	parent:             ^Node,
	kids:               [dynamic]^Node,
	position:           [2]f32,
	max_size:           [2]f32,
	size:               [2]f32,
	content_align:      [2]f32,
	content_min_size:   [2]f32,
	used_space:         [2]f32,
	padding:            [4]f32,
	growable_kid_count: int,
	spacing:            f32,
	grow:               [2]bool,
	vertical:           bool,
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

destroy :: proc() {
	delete(ctx.nodes)
	delete(ctx.roots)
	delete(ctx.stack)
	delete(ctx.id_stack)
}

ctx: ^Context

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
	return fnv32a(bytes, ctx.id_stack[len(ctx.id_stack) - 1])
}

hash_loc :: proc(loc: runtime.Source_Code_Location) -> Id {
	hash := hash_bytes(transmute([]byte)loc.file_path)
	hash = hash ~ (Id(loc.line) * FNV1A32_PRIME)
	hash = hash ~ (Id(loc.column) * FNV1A32_PRIME)
	return hash
}

push_id_int :: proc(num: int) {
	append(&ctx.id_stack, hash_int(num))
}

push_id_string :: proc(str: string) {
	append(&ctx.id_stack, hash_string(str))
}

push_id_other :: proc(id: Id) {
	append(&ctx.id_stack, id)
}

push_id :: proc {
	push_id_int,
	push_id_string,
	push_id_other,
}

pop_id :: proc() {
	pop(&ctx.id_stack)
}

begin :: proc() {
	ctx.frame_start_time = time.now()

	reserve(&ctx.nodes, 128)

	clear(&ctx.id_stack)
	clear(&ctx.stack)
	clear(&ctx.roots)
	clear(&ctx.nodes)

	push_id(Id(FNV1A32_OFFSET_BASIS))
	ctx.current_node = nil
}

end :: proc() {
	ctx.frame_duration = time.since(ctx.frame_start_time)
	for root in ctx.roots {
		root.box = {root.position - root.size / 2, root.position + root.size / 2}
		node_grow_kids_recursively(root)
		node_solve_box_recursively(root)
		node_draw_recursively(root)
	}
}

COLORS := [?]kn.Color{kn.SkyBlue, kn.LightGoldenrodYellow, kn.PaleGreen}

push_node :: proc(node: ^Node) {
	append(&ctx.stack, node)
	ctx.current_node = ctx.stack[len(ctx.stack) - 1]
}

pop_node :: proc() {
	pop(&ctx.stack)
	if len(ctx.stack) <= 0 {
		ctx.current_node = nil
		return
	}
	ctx.current_node = ctx.stack[len(ctx.stack) - 1]
}

begin_node :: proc(node: Node, loc := #caller_location) -> (self: ^Node) {
	append(&ctx.nodes, node)
	self = &ctx.nodes[len(ctx.nodes) - 1]
	self.parent = ctx.current_node
	self.kids = make([dynamic]^Node, 0, 16, allocator = context.temp_allocator)
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
	self := ctx.current_node
	if self == nil {
		return
	}
	i := int(self.vertical)
	self.content_min_size = self.used_space + self.padding.xy + self.padding.zw
	self.content_min_size[i] += self.spacing * f32(max(len(self.kids) - 1, 0))
	self.size = linalg.max(self.size, self.content_min_size)
	pop_node()
	if ctx.current_node != nil {
		node_on_child_end(ctx.current_node, self)
	}
}

do_node :: proc(node: Node, loc := #caller_location) {
	begin_node(node, loc)
	end_node()
}

node_on_child_end :: proc(self: ^Node, child: ^Node) {
	if self.vertical {
		self.used_space.y += child.size.y
		self.used_space.x = max(self.used_space.x, child.size.x)
	} else {
		self.used_space.x += child.size.x
		self.used_space.y = max(self.used_space.y, child.size.y)
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

	remaining_space :=
		self.size[i] -
		self.used_space[i] -
		self.padding[i] -
		self.padding[i + 2] -
		self.spacing * f32(len(self.kids) - 1)

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
		smallest := growables[0].size[i]
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
		if node.grow[j] {
			node.size[j] = max(node.size[j], self.size[j] - self.padding[j] - self.padding[j + 2])
		}
		node.size[j] = min(node.size[j], self.size[j] - self.padding[j] - self.padding[j + 2])
		node.position[j] = self.padding[j]
		node.position[i] = offset_along_axis + remaining_space * self.content_align[i]
		offset_along_axis += node.size[i] + self.spacing
		node_grow_kids_recursively(node)
	}
}

node_draw_recursively :: proc(self: ^Node, depth := 0) {
	kn.add_box(self.box, 4, paint = COLORS[depth % len(COLORS)])
	kn.push_scissor(kn.make_box(self.box))
	kn.add_string(
		fmt.tprintf("%.0fx%.0f", self.size.x, self.size.y),
		12,
		(self.box.lo + self.box.hi) / 2,
		align = 0.5,
		paint = kn.Black,
	)
	for node in self.kids {
		node_draw_recursively(node, depth + 1)
	}
	kn.pop_scissor()
	kn.add_box_lines(self.box, 1, 4, paint = kn.Black)
}

main :: proc() {
	sdl2.Init({.VIDEO})
	defer sdl2.Quit()

	window := sdl2.CreateWindow("OPAL", 100, 100, 800, 600, {.RESIZABLE})
	defer sdl2.DestroyWindow(window)

	platform := kn.make_platform_sdl2glue(window)
	defer kn.destroy_platform(&platform)

	kn.start_on_platform(platform)
	defer kn.shutdown()

	ctx = new(Context)
	// defer destroy()
	//

	menu_item :: proc(index: int = 0) {
		begin_node(
			{
				size = {},
				max_size = {math.F32_MAX, 20 + f32(index) * 20},
				grow = {true, true},
				padding = 4,
				spacing = 4,
			},
		)
		do_node({size = {50 + f32(index) * 20, 20}, max_size = math.F32_MAX, grow = {true, false}})
		do_node({size = {20, 20}})
		end_node()
	}

	loop: for {
		sdl2.Delay(10)
		event: sdl2.Event
		for sdl2.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break loop
			case .KEYDOWN:
				if event.key.keysym.scancode == .SPACE {
					// build_ui()
				}
			case .MOUSEMOTION:
				ctx.mouse_position = {f32(event.motion.x), f32(event.motion.y)}
			case .WINDOWEVENT:
				if event.window.event == .RESIZED {
					kn.set_size(event.window.data1, event.window.data2)
				}
			}
		}

		kn.new_frame()

		begin()
		center := linalg.array_cast(kn.get_size(), f32) / 2
		begin_node(
			{
				position = center,
				size = linalg.max((ctx.mouse_position - center) * 2, 100),
				padding = 4,
				spacing = 4,
				vertical = true,
				content_align = {1 = 0.5},
			},
		)
		menu_item(1)
		menu_item(2)
		menu_item(3)
		end_node()
		end()

		// for &root in ctx.roots do draw_element(&root)
		kn.set_paint(kn.Yellow)
		kn.add_string(fmt.tprintf("FPS: %.0f", kn.get_fps()), 16, 0)

		kn.set_clear_color(kn.DarkSlateGray)
		kn.present()

		free_all(context.temp_allocator)
	}
}

