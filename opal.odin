package opal

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:reflect"
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
// **Flex Layout**
//
// Has a size limit and can align and justify content.  Each child node can specify its own flex behavior.  Children are resized by the layout based on their sizing config since every node has a minimum and maximum size.
//
Flex_Layout :: struct {
	spacing:  f32,
	vertical: bool,
	align:    f32,
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

Layout_Variant :: union {
	Basic_Layout,
	Flex_Layout,
	Wrap_Layout,
	Grid_Layout,
}

Node :: struct {
	// If the parent is `nil` then the node will be in the `roots` array of the context
	parent:        ^Node,

	// Any nodes contained within and dependant on this node
	kids:          [dynamic]^Node,

	// The state required for placing child nodes
	layout:        Layout,

	// The node's own size settings for layout within its parent
	sizing:        [2]Size_Config,

	// A unique hashed identifier
	id:            Id,

	// The final bounding box of the node after the layout phase is complete
	box:           Box,

	// Input state for the current frame
	// hovered:         bool,
	// active:          bool,
	// focused:         bool,

	// If overflowing contents are clipped and hidden
	hide_overflow: bool,

	// If scrolling is enabled
	// enable_scroll_x: bool,
	// enable_scroll_y: bool,

	// Z-index for visual sorting and input propagation
	z_index:       u32,

	// Data provided to user methods
	user_data:     rawptr,

	// If not `nil`, this will be called before `on_draw` every frame as long as animations are enabled
	// on_animate:      proc(self: ^Node),

	// Called instead of the default drawing procedure if not `nil`
	on_draw:       proc(self: ^Node),
}

Context :: struct {
	// Input state
	mouse_position:   Vector2,
	hovered_node:     ^Node,
	focused_node:     ^Node,

	// Contiguous storage of all nodes in the UI
	elements:         [dynamic]Node,

	// All nodes wihout a parent are stored here
	roots:            [dynamic]^Node,

	// All currently active nodes being processed
	stack:            [dynamic]^Node,

	// The hash stack
	id_stack:         [dynamic]Id,

	// The top-most element of the stack
	current_element:  ^Node,

	// Profiling state
	frame_start_time: time.Time,
	frame_duration:   time.Duration,
}

ctx: Context

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

begin_root_element :: proc(config: Root_Node_Config, loc := #caller_location) {
	begin_element(config, loc)
	ctx.current_element.box.lo = config.position
}

begin_element :: proc(config: Node_Config, loc := #caller_location) {
	element := Node {
		parent = ctx.current_element,
		id     = hash_loc(loc),
	}
	reserve(&element.kids, 16)

	append(&ctx.elements, element)
	ctx.current_element = &ctx.elements[len(ctx.elements) - 1]
	if element.parent == nil {
		append(&ctx.roots, ctx.current_element)
	} else {
		append(&element.parent.kids, ctx.current_element)
	}
	append(&ctx.stack, ctx.current_element)

}

end_element :: proc() {
	element := ctx.current_element

	pop(&ctx.stack)
	if len(ctx.stack) > 0 {
		ctx.current_element = ctx.stack[len(ctx.stack) - 1]
	} else {
		ctx.current_element = nil
	}

	element.extent = clamp(element.extent, element.min_extent, element.max_extent)
	element.span = clamp(element.span, element.min_span, element.max_span)

	next_element := ctx.current_element

	if next_element != nil {
		next_element.used_extent += element.extent
		next_element.used_span = max(next_element.used_span, element.span)
	}
}

grow_element :: proc(element: ^Node) {

}

get_element_size :: proc(element: ^Node) -> (width, height: f32) {
	if element.vertical {

	}
}

grow_kids :: proc(element: ^Node) {
	total_span := element.span - element.padding.before_span - element.padding.after_span
	total_extent :=
		element.extent -
		element.padding.before_extent -
		element.padding.after_extent -
		element.kid_gap * f32(element.kid_count - 1)

	if element.vertical {
		total_extent, total_span = total_span, total_extent
	}

	kids_to_grow := element.growable_kid_count
	target_extent := total_extent / kids_to_grow

	for index in element.first_kid ..< element.first_kid + element.kid_count {
		kid := &ctx.elements[index]
		if kid.extent_will_grow {
			kid.extent = target_extent
		}
		grow_kids(&kid)
	}

	// overflow := element.used_extent - total_extent
	// if overflow > 0 && len(element.kids) > 0 {
	// 	element.kids[0].extent -= overflow
	// }
}

solve_root_position :: proc(element: ^Node) {
	if element.axis == .Horizontal {
		element.box.hi = element.box.lo + {element.extent, element.span}
	} else {
		element.box.hi = element.box.lo + {element.span, element.extent}
	}
	solve_kid_positions(element)
}

solve_kid_positions :: proc(element: ^Node) {
	extent_offset := element.padding.before_extent
	span_offset := element.padding.before_span
	for index in element.first_kid ..< element.first_kid + element.kid_count {
		kid := &ctx.elements[index]
		kid.extent_offset = extent_offset
		kid.span_offset = span_offset
		kid.box = solve_kid_box(element, &kid)
		solve_kid_positions(&kid)
		extent_offset += kid.extent + element.kid_gap
	}
}

solve_kid_box :: proc(parent, kid: ^Node) -> Box {
	if parent.vertical {
		position := parent.box.lo + {kid.span_offset, kid.extent_offset}
		return Box{position, position + {kid.span, kid.extent}}
	}
	position := parent.box.lo + {kid.extent_offset, kid.span_offset}
	return Box{position, position + {kid.extent, kid.span}}
}

@(deferred_none = __basic_element)
root_element :: proc(config: Root_Node_Config, loc := #caller_location) {
	begin_root_element(config, loc)
}

@(deferred_none = __basic_element)
basic_element :: proc(config: Node_Config, loc := #caller_location) {
	begin_element(config, loc)
}

@(private)
__basic_element :: proc() {
	end_element()
}

begin :: proc() {
	ctx.frame_start_time = time.now()

	clear(&ctx.id_stack)
	clear(&ctx.stack)
	clear(&ctx.leaves)
	clear(&ctx.roots)

	free_all(context.temp_allocator)

	push_id(Id(FNV1A32_OFFSET_BASIS))
	ctx.current_element = nil
}

end :: proc() {
	for &root in ctx.roots do grow_kids(&root)
	for &root in ctx.roots do solve_root_position(&root)
	ctx.frame_duration = time.since(ctx.frame_start_time)
}

print_element :: proc(element: ^Node, depth: int = 0) {
	for i in 0 ..< depth {
		fmt.print("| ")
	}
	fmt.printfln(
		"(%i) [%.2f, %.2f] (%.2f)",
		element.id,
		element.box.lo,
		element.box.hi,
		element.box.hi - element.box.lo,
	)
	for &kid in element.kids {
		print_element(&kid, depth + 1)
	}
}

COLORS := [?]kn.Color{kn.Purple, kn.HotPink, kn.SkyBlue}

build_ui :: proc() {
	menu_item_element :: proc(text: string, icon: rune) {
		{basic_element({size = {{grow = true}, {max = 40}}, padding = PADDING_ALL(4), kid_gap = 4})
			{basic_element(
					{
						size = {{grow = true}, {grow = true}},
						axis = .Horizontal,
						padding = PADDING_ALL(4),
					},
				)
				{basic_element(
						{size = {{max = rand.float32_range(30, 100), grow = true}, {grow = true}}},
					)}
			}
			{basic_element({size = {{min, max = 30}, {min, max = 30}}})}
		}
	}

	begin()
	{root_element(
			{
				position = 200,
				size = {FIT(100, 300), FIT()},
				padding = PADDING_ALL(4),
				kid_gap = 4,
				vertical = true,
			},
		)
		menu_item_element("New", '?')
		menu_item_element("Open", '?')
		menu_item_element("Save", '?')
		menu_item_element("Quit", '?')
	}
	end()
	fmt.printfln("Built UI in %.3fms", time.duration_milliseconds(ctx.frame_duration))
}

main :: proc() {
	build_ui()

	// for &root in ctx.roots do print_element(&root)

	//------------------------------//
	//- NOW DRAW THE STATIC LAYOUT -//
	//------------------------------//

	sdl2.Init({.VIDEO})
	defer sdl2.Quit()

	window := sdl2.CreateWindow("OPAL", 100, 100, 800, 600, {})
	defer sdl2.DestroyWindow(window)

	platform := kn.make_platform_sdl2glue(window)
	defer kn.destroy_platform(&platform)

	kn.start_on_platform(platform)
	defer kn.shutdown()


	draw_element :: proc(element: ^Node, depth: int = 0) {
		kn.set_paint(COLORS[depth % len(COLORS)])
		kn.add_box(element.box, 3)
		for &kid in element.kids {
			draw_element(&kid, depth + 1)
		}
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
					build_ui()
				}
			}
		}

		kn.new_frame()

		for &root in ctx.roots do draw_element(&root)
		kn.set_paint(kn.Green)
		kn.add_string(fmt.tprintf("FPS: %.0f", kn.get_fps()), 20, 0)

		kn.present()
	}
}

