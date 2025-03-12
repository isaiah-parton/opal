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

Padding :: struct {
	before_extent, after_extent, before_span, after_span: f32,
}

Dimension_Config :: struct {
	min:   f32,
	max:   f32,
	modes: Sizing_Modes,
}

FIXED :: proc(value: f32) -> Dimension_Config {
	return Dimension_Config{min = value, max = value}
}

GROW :: proc(min: f32 = 0, max: f32 = math.F32_MAX) -> Dimension_Config {
	return Dimension_Config{min = min, max = max, modes = {.Grow}}
}

FIT :: proc(min: f32 = 0, max: f32 = math.F32_MAX) -> Dimension_Config {
	return Dimension_Config{min = min, max = max, modes = {.Fit}}
}

PADDING_ALL :: proc(amount: f32) -> Padding_Config {
	return Padding_Config{amount, amount, amount, amount}
}

Sizing_Mode :: enum {
	Grow,
	Fit,
}

Sizing_Modes :: bit_set[Sizing_Mode;u8]

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

Element_Config :: struct {
	size:           Size_Config,
	child_gap:      f32,
	span_alignment: f32,
	axis:           Axis,
	padding:        Padding_Config,
}

Element_Input_Flag :: enum {
	Is_Focused,
}

Root_Element_Config :: struct {
	using base: Element_Config,
	position:   Vector2,
}

Element :: struct {
	using layout: Element_Layout,
	children:     [dynamic]Element,
	growables:    [dynamic]^Element,
	shrinkables:  [dynamic]^Element,
	padding:      Padding,
	parent:       ^Element,
	box:          Box,
	id:           Id,
	axis:         Axis,
	hidden:       bool,
}

Element_Layout :: struct {
	// Span alignment
	span_alignment: f32,
	// Relative position on layout axis
	extent_offset:  f32,
	// Relative position on layout counter-axis
	span_offset:    f32,
	// Size on layout axis
	extent:         f32,
	min_extent:     f32,
	max_extent:     f32,
	used_extent:    f32,
	// Size on layout counter-axis
	span:           f32,
	min_span:       f32,
	max_span:       f32,
	used_span:      f32,
	// Gap between children along layout axis
	child_gap:      f32,
	// Sizing modes
	extent_modes:   Sizing_Modes,
	span_modes:     Sizing_Modes,
	invert_axis:    bool,
}

Context :: struct {
	mouse_position:   Vector2,
	roots:            [dynamic]Element,
	leaves:           [dynamic]^Element,
	element_stack:    [dynamic]^Element,
	id_stack:         [dynamic]Id,
	current_element:  ^Element,
	frame_start_time: time.Time,
	frame_duration:   time.Duration,
}

ctx: Context

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

begin_root_element :: proc(config: Root_Element_Config, loc := #caller_location) {
	begin_element(config, loc)
	ctx.current_element.box.lo = config.position
}

begin_element :: proc(config: Element_Config, loc := #caller_location) {
	element := Element {
		parent         = ctx.current_element,
		id             = hash_loc(loc),
		child_gap      = config.child_gap,
		axis           = config.axis,
		span_alignment = config.span_alignment,
		children       = make([dynamic]Element, allocator = context.temp_allocator),
		growables      = make([dynamic]^Element, allocator = context.temp_allocator),
		shrinkables    = make([dynamic]^Element, allocator = context.temp_allocator),
	}

	if element.axis == .Horizontal {
		element.padding = Padding {
			before_extent = config.padding.left,
			after_extent  = config.padding.right,
			before_span   = config.padding.top,
			after_span    = config.padding.bottom,
		}
	} else {
		element.padding = Padding {
			before_extent = config.padding.top,
			after_extent  = config.padding.bottom,
			before_span   = config.padding.left,
			after_span    = config.padding.right,
		}
	}

	layout_axis := element.axis if element.parent == nil else element.parent.axis

	element.invert_axis = layout_axis == element.axis

	if layout_axis == .Horizontal {
		element.span_modes = config.size.height.modes
		element.min_span = config.size.height.min
		element.max_span = config.size.height.max

		element.extent_modes = config.size.width.modes
		element.min_extent = config.size.width.min
		element.max_extent = config.size.width.max
	} else {
		element.span_modes = config.size.width.modes
		element.min_span = config.size.width.min
		element.max_span = config.size.width.max

		element.extent_modes = config.size.height.modes
		element.min_extent = config.size.height.min
		element.max_extent = config.size.height.max
	}

	if element.parent == nil {
		append(&ctx.roots, element)
		ctx.current_element = &ctx.roots[len(ctx.roots) - 1]
	} else {
		append(&element.parent.children, element)
		ctx.current_element = &element.parent.children[len(element.parent.children) - 1]

		if (.Grow in element.extent_modes) {
			append(&element.parent.growables, ctx.current_element)
		}
	}

	append(&ctx.element_stack, ctx.current_element)
}

end_element :: proc() {
	element := ctx.current_element

	if len(element.children) == 0 {
		append(&ctx.leaves, element)
	}

	pop(&ctx.element_stack)
	if len(ctx.element_stack) > 0 {
		ctx.current_element = ctx.element_stack[len(ctx.element_stack) - 1]
	} else {
		ctx.current_element = nil
	}

	if element.extent_modes & {.Fit} != {} {
		if element.invert_axis {
			element.extent = max(
				element.extent,
				element.used_extent +
				element.padding.before_extent +
				element.padding.after_extent +
				element.child_gap * f32(len(element.children) - 1),
			)
		} else {
			element.extent = max(
				element.extent,
				element.used_span + element.padding.before_span + element.padding.after_span,
			)
		}
	}
	if element.span_modes & {.Fit} != {} {
		if element.invert_axis {
			element.span = max(
				element.span,
				element.used_span + element.padding.before_span + element.padding.after_span,
			)
		} else {
			element.span = max(
				element.span,
				element.used_extent +
				element.padding.before_extent +
				element.padding.after_extent +
				element.child_gap * f32(len(element.children) - 1),
			)
		}
	}

	element.extent = clamp(element.extent, element.min_extent, element.max_extent)
	element.span = clamp(element.span, element.min_span, element.max_span)

	effective_span := element.span
	if .Grow in element.span_modes {
		effective_span = max(
			element.used_span if element.invert_axis else element.used_extent,
			effective_span,
		)
	}

	next_element := ctx.current_element

	if next_element != nil {
		next_element.used_extent += element.extent
		next_element.used_span = max(next_element.used_span, effective_span)
	}
}

grow_element_children :: proc(element: ^Element) {
	total_extent := element.span - element.padding.before_span - element.padding.after_span
	total_span :=
		element.extent -
		element.padding.before_extent -
		element.padding.after_extent -
		element.child_gap * f32(len(element.children) - 1)

	if element.invert_axis {
		total_extent, total_span = total_span, total_extent
	}

	remaining_extent := total_extent - element.used_extent

	grow_extent_to := remaining_extent / f32(len(element.growables))
	grow_span_to := total_span

	for &child in element.children {
		if .Grow in child.extent_modes {
			child.extent += (grow_extent_to - child.extent)
			child.extent = max(child.extent, 0)
		}
		if .Grow in child.span_modes {
			child.span = min(child.max_span, grow_span_to)
		}
	}

	overflow := element.used_extent - total_extent
	if overflow > 0 && len(element.children) > 0 {
		element.children[0].extent -= overflow
	}

	for &child in element.children do grow_element_children(&child)
}

solve_root_position :: proc(element: ^Element) {
	if element.axis == .Horizontal {
		element.box.hi = element.box.lo + {element.extent, element.span}
	} else {
		element.box.hi = element.box.lo + {element.span, element.extent}
	}
	solve_child_positions(element)
}

solve_child_positions :: proc(element: ^Element) {
	extent_offset := element.padding.before_extent
	span_offset := element.padding.before_span
	for &child in element.children {
		child.extent_offset = extent_offset
		child.span_offset = span_offset
		child.box = solve_child_box(element, &child)
		solve_child_positions(&child)
		extent_offset += child.extent + element.child_gap
	}
}

solve_child_box :: proc(parent, child: ^Element) -> Box {
	if parent.axis == .Horizontal {
		position := parent.box.lo + {child.extent_offset, child.span_offset}
		return Box{position, position + {child.extent, child.span}}
	}
	position := parent.box.lo + {child.span_offset, child.extent_offset}
	return Box{position, position + {child.span, child.extent}}
}

@(deferred_none = __basic_element)
root_element :: proc(config: Root_Element_Config, loc := #caller_location) {
	begin_root_element(config, loc)
}

@(deferred_none = __basic_element)
basic_element :: proc(config: Element_Config, loc := #caller_location) {
	begin_element(config, loc)
}

@(private)
__basic_element :: proc() {
	end_element()
}

begin :: proc() {
	ctx.frame_start_time = time.now()

	clear(&ctx.id_stack)
	clear(&ctx.element_stack)
	clear(&ctx.leaves)
	clear(&ctx.roots)

	free_all(context.temp_allocator)

	push_id(Id(FNV1A32_OFFSET_BASIS))
	ctx.current_element = nil
}

end :: proc() {
	for &root in ctx.roots do grow_element_children(&root)
	for &root in ctx.roots do solve_root_position(&root)
	ctx.frame_duration = time.since(ctx.frame_start_time)
}

print_element :: proc(element: ^Element, depth: int = 0) {
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
	for &child in element.children {
		print_element(&child, depth + 1)
	}
}

COLORS := [?]kn.Color{kn.Purple, kn.HotPink, kn.SkyBlue}

build_ui :: proc() {
	menu_item_element :: proc(text: string, icon: rune) {
		{basic_element(
				{
					size = {GROW(), FIT(20)},
					padding = PADDING_ALL(4),
					child_gap = 4,
					axis = .Horizontal,
				},
			)
			{basic_element({size = {GROW(), GROW()}, axis = .Horizontal})
				{basic_element({size = {FIXED(10), GROW()}})}
			}
			{basic_element({size = {FIXED(30), FIXED(30)}})}
		}
	}

	begin()
	{root_element(
			{
				position = 200,
				size = {FIT(100, 300), FIT()},
				padding = PADDING_ALL(4),
				child_gap = 4,
				axis = .Vertical,
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


	draw_element :: proc(element: ^Element, depth: int = 0) {
		kn.set_paint(COLORS[depth % len(COLORS)])
		kn.add_box(element.box, 3)
		for &child in element.children {
			draw_element(&child, depth + 1)
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

