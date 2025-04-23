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
	p:            [4]f32,
	px:           f32,
	py:           f32,
	pl:           f32,
	pt:           f32,
	pr:           f32,
	pb:           f32,
	gap:          f32,
	fit:          bool,
	fit_x:        bool,
	fit_y:        bool,
	grow:         bool,
	grow_x:       bool,
	grow_y:       bool,
	w:            f32,
	h:            f32,
	max_w:        f32,
	max_h:        f32,
	size:         [2]f32,
	max_size:     [2]f32,
	align_x:      f32,
	align_y:      f32,
	fill:         kn.Paint_Option,
	stroke:       kn.Paint_Option,
	stroke_width: f32,
	radius:       f32,
}

node_configure :: proc(self: ^Node, config: Node_Config) {
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
	self.content_align = {config.align_x, config.align_y}
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

	// The maximum size the node is allowed to grow to
	max_size:           [2]f32,

	// The node's actual size, this is subject to change until `end()` is called
	// The initial value is effectively the node's minimum size
	size:               [2]f32,

	// If the node will be grown to fill available space
	grow:               [2]bool,

	// If the node will grow to acommodate its kids
	fit:                [2]bool,

	// Values for the node's children layout
	content_align:      [2]f32,
	content_size:       [2]f32,
	padding:            [4]f32,
	spacing:            f32,
	vertical:           bool,
	growable_kid_count: int,

	// Input state
	is_hovered:         bool,
	is_invisible:       bool,
	has_hovered_child:  bool,

	// Z index (higher values appear in front of lower ones)
	z_index:            u32,

	// Appearance
	text:               string,
	text_layout:        kn.Text,
	style:              Node_Style,

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
	hovered_id:       Id,
	focused_id:       Id,

	// Map of node ids
	nodes_by_id:      map[Id]^Node,

	// Contiguous storage of all nodes in the UI
	nodes:            [dynamic]Node,

	// All nodes wihout a parent are stored here for layout solving
	// They are the root nodes of their layout trees
	roots:            [dynamic]^Node,

	// The stack of nodes being declared
	stack:            [dynamic]^Node,

	// The hash stack
	id_stack:         [dynamic]Id,

	// The top-most element of the stack
	current_node:     ^Node,

	// Profiling state
	frame_start_time: time.Time,
	frame_duration:   time.Duration,
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

//
// Clear the UI construction state for a new frame
//
begin :: proc() {
	ctx := global_ctx
	ctx.frame_start_time = time.now()

	clear(&ctx.id_stack)
	clear(&ctx.stack)
	clear(&ctx.roots)
	clear(&ctx.nodes)

	push_id(Id(FNV1A32_OFFSET_BASIS))
	ctx.current_node = nil
	ctx.hovered_node = nil
	ctx.focused_node = nil
}

//
// Ends UI declaration and constructs the final layout, node boxes are only valid after this is called
//
end :: proc() {
	ctx := global_ctx
	ctx.frame_duration = time.since(ctx.frame_start_time)
	for root in ctx.roots {
		root.box = {root.position - root.size / 2, root.position + root.size / 2}

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
	if ctx.hovered_node != nil {
		kn.add_box_lines(ctx.hovered_node.box, 1, paint = kn.Blue)
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
		fill_paint = kn.rgba_from_hex("#f5b041") or_else kn.Black,
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
	self.is_dead = false
	if self.text != {} {
		self.text_layout = kn.make_text(self.text, 12)
		self.size = linalg.max(self.size, self.text_layout.size)
	}
	self.content_size = 0
	self.has_hovered_child = false
	self.is_hovered = ctx.hovered_id == self.id
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

do_node :: proc(node: Node, loc := #caller_location) {
	begin_node(node, loc)
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

		// Continue the recursion
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
}

node_draw_recursively :: proc(self: ^Node, depth := 0) {
	node_receive_input(self)
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
	if self.has_hovered_child {
		kn.add_box_lines(self.box, 1, paint = kn.LightGreen)
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
				fit = true,
				padding = 4,
				content_align = {0, 0.5},
				style = {fill_paint = kn.DarkSlateGray, radius = 4},
			},
		)
		do_node({text = text, max_size = math.F32_MAX, style = text_node_style()})
		do_node({size = {10, 0}, max_size = math.F32_MAX, grow = true})
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
				width, height: i32
				sdl3.GetWindowSize(window, &width, &height)
				kn.set_size(width, height)
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
				fit = true,
				style = {fill_paint = kn.DimGray, radius = 4},
			},
		)
		for item, item_index in MENU_ITEMS {
			push_id(item_index)
			menu_item(item)
			pop_id()
		}
		end_node()

		begin_node(
			{
				position = {center.x, 100},
				padding = 10,
				spacing = 5,
				fit = true,
				style = default_node_style(),
			},
		)
		do_node({size = 20, style = default_node_style()})
		do_node({size = 20, style = default_node_style()})
		do_node({size = 20, style = default_node_style()})
		end_node()

		end()

		kn.set_paint(kn.PaleTurquoise)
		kn.add_string(fmt.tprintf("FPS: %.0f", kn.get_fps()), 16, 0)
		kn.add_string(fmt.tprintf("%.0f", ctx.mouse_position), 16, {0, 16})

		kn.set_clear_color(kn.Black)
		kn.present()

		free_all(context.temp_allocator)
	}
}

