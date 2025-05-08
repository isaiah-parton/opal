package example

import opal ".."
import kn "../../katana"
import "../../katana/sdl3glue"
import "../lucide"
import tw "../tailwind_colors"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:time"
import "vendor:sdl3"
import "vendor:wgpu"

Vertex :: struct {
	pos:       [4]f32,
	tex_coord: [2]f32,
}

vertex :: proc(pos: [3]f32, tex_coord: [2]f32) -> Vertex {
	return Vertex{pos = {pos.x, pos.y, pos.z, 1.0}, tex_coord = tex_coord}
}

Example_Renderer :: struct {
	vertex_buf:    wgpu.Buffer,
	index_buf:     wgpu.Buffer,
	index_count:   uint,
	bind_group:    wgpu.BindGroup,
	uniform_buf:   wgpu.Buffer,
	pipeline:      wgpu.RenderPipeline,
	pipeline_wire: Maybe(wgpu.RenderPipeline),
}

example_renderer_init :: proc(self: ^Example_Renderer, device: wgpu.Device) {
	self.vertex_buf = wgpu.DeviceCreateBufferWithDataSlice(
	device,
	&{label = "Vertex Buffer", usage = {.Vertex}},
	[]Vertex {
		// top (0, 0, 1)
		vertex({-1, -1, 1}, {0, 0}),
		vertex({1, -1, 1}, {1, 0}),
		vertex({1, 1, 1}, {1, 1}),
		vertex({-1, 1, 1}, {0, 1}),
		// bottom (0, 0, -1)
		vertex({-1, 1, -1}, {1, 0}),
		vertex({1, 1, -1}, {0, 0}),
		vertex({1, -1, -1}, {0, 1}),
		vertex({-1, -1, -1}, {1, 1}),
		// right (1, 0, 0)
		vertex({1, -1, -1}, {0, 0}),
		vertex({1, 1, -1}, {1, 0}),
		vertex({1, 1, 1}, {1, 1}),
		vertex({1, -1, 1}, {0, 1}),
		// left (-1, 0, 0)
		vertex({-1, -1, 1}, {1, 0}),
		vertex({-1, 1, 1}, {0, 0}),
		vertex({-1, 1, -1}, {0, 1}),
		vertex({-1, -1, -1}, {1, 1}),
		// front (0, 1, 0)
		vertex({1, 1, -1}, {1, 0}),
		vertex({-1, 1, -1}, {0, 0}),
		vertex({-1, 1, 1}, {0, 1}),
		vertex({1, 1, 1}, {1, 1}),
		// back (0, -1, 0)
		vertex({1, -1, 1}, {0, 0}),
		vertex({-1, -1, 1}, {1, 0}),
		vertex({-1, -1, -1}, {1, 1}),
		vertex({1, -1, -1}, {0, 1}),
	},
	)

	self.index_buf = wgpu.DeviceCreateBufferWithDataSlice(
	device,
	&{label = "Index Buffer", usage = {.Index}},
	[]u16 {
		0,
		1,
		2,
		2,
		3,
		0, // top
		4,
		5,
		6,
		6,
		7,
		4, // bottom
		8,
		9,
		10,
		10,
		11,
		8, // right
		12,
		13,
		14,
		14,
		15,
		12, // left
		16,
		17,
		18,
		18,
		19,
		16, // front
		20,
		21,
		22,
		22,
		23,
		20, // back
	},
	)

	bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		device,
		&{
			entryCount = 1,
			entries = ([^]wgpu.BindGroupLayoutEntry)(
				&[?]wgpu.BindGroupLayoutEntry {
					{
						binding = 0,
						visibility = {.Vertex},
						buffer = {minBindingSize = 64, type = .Uniform},
					},
				},
			),
		},
	)

	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		device,
		&{bindGroupLayouts = &bind_group_layout},
	)

	shader := wgpu.DeviceCreateShaderModule(
		device,
		&{
			nextInChain = &wgpu.ShaderSourceWGSL {
				sType = .ShaderSourceWGSL,
				code = #load("shader.wgsl"),
			},
		},
	)
}

do_window_button :: proc(icon: rune, color: kn.Color, loc := #caller_location) -> bool {
	using opal
	node := do_node({
			p = 3,
			fit = true,
			text = string_from_rune(icon),
			font_size = 20,
			fg = tw.NEUTRAL_300,
			font = &lucide.font,
			max_size = math.F32_MAX,
			widget = true,
			on_animate = proc(self: ^Node) {
				self.style.background_paint = kn.fade(tw.ROSE_500, self.transitions[0])
				self.style.foreground_paint = kn.mix(
					self.transitions[0],
					tw.ROSE_50,
					tw.NEUTRAL_900,
				)
				self.transitions[1] +=
					(f32(i32(self.is_active)) - self.transitions[1]) * rate_per_second(7)
				self.transitions[0] +=
					(f32(i32(self.is_hovered)) - self.transitions[0]) * rate_per_second(14)
			},
		}, loc = loc)
	assert(node != nil)
	return node.was_active && !node.is_active && node.is_hovered
}

do_button :: proc(label: union #no_nil {
		string,
		rune,
	}, font: ^kn.Font = nil, font_size: f32 = 12, radius: [4]f32 = 3, loc := #caller_location) -> bool {
	using opal
	node := do_node({
			p = 3,
			radius = radius,
			fit = true,
			text = label.(string) or_else string_from_rune(label.(rune)),
			font_size = font_size,
			fg = tw.NEUTRAL_300,
			font = font,
			max_size = math.F32_MAX,
			widget = true,
			on_animate = proc(self: ^Node) {
				self.style.background_paint = kn.fade(
					tw.NEUTRAL_600,
					0.3 + f32(i32(self.is_hovered)) * 0.3,
				)
				self.transitions[1] +=
					(f32(i32(self.is_active)) - self.transitions[1]) * rate_per_second(7)
				self.transitions[0] +=
					(f32(i32(self.is_hovered)) - self.transitions[0]) * rate_per_second(14)
			},
		}, loc = loc)
	assert(node != nil)
	return node.was_active && !node.is_active && node.is_hovered
}

do_menu_item :: proc(label: string, icon: rune, loc := #caller_location) {
	using opal
	push_id(hash(loc))

	begin_node({
		p = 3,
		pr = 12,
		radius = 3,
		fit = true,
		gap = 6,
		max_size = math.F32_MAX,
		grow_x = true,
		content_align_y = 0.5,
		widget = true,
		on_animate = proc(self: ^Node) {
			self.style.background_paint = kn.fade(
				tw.NEUTRAL_600,
				self.transitions[0] * 0.3 + self.transitions[1] * 0.3,
			)
			self.transitions[1] +=
				(f32(i32(self.is_active || self.has_active_child)) - self.transitions[1]) *
				rate_per_second(14)
			self.transitions[0] +=
				(f32(i32(self.is_hovered || self.has_hovered_child)) - self.transitions[0]) *
				rate_per_second(14)
		},
	})
	do_node(
		{
			text = string_from_rune(icon),
			font = &lucide.font,
			font_size = 14,
			fit = true,
			fg = tw.NEUTRAL_300,
		},
	)
	do_node({text = label, font_size = 12, fit = true, fg = tw.NEUTRAL_300})
	end_node()
	pop_id()
}

@(deferred_out = __do_menu)
do_menu :: proc(label: string, loc := #caller_location) -> bool {
	using opal
	push_id(hash(loc))
	node := begin_node({
		p = 3,
		radius = 3,
		fit = true,
		text = label,
		font_size = 12,
		fg = tw.NEUTRAL_300,
		widget = true,
		on_animate = proc(self: ^Node) {
			self.style.background_paint = kn.fade(tw.NEUTRAL_600, 0.3 + self.transitions[0] * 0.3)
			self.transitions[1] +=
				(f32(i32(self.is_active)) - self.transitions[1]) * rate_per_second(7)
			self.transitions[0] +=
				(f32(i32(self.is_hovered)) - self.transitions[0]) * rate_per_second(14)
			if self.is_hovered && self.parent != nil && self.parent.has_focused_child {
				focus_node(self.id)
			}
		},
	})

	assert(node != nil)

	is_open := node.is_focused || node.has_focused_child

	if is_open {
		begin_node(
			{
				shadow_size = 5,
				shadow_color = {0, 0, 0, 128},
				bounds = Box{0, kn.get_size()},
				z = 999,
				abs = true,
				relative_pos = {0, 1},
				pos = {0, 4},
				fit = true,
				p = 3,
				gap = 3,
				radius = 3,
				bg = tw.NEUTRAL_800,
				vertical = true,
			},
		)
	}

	pop_id()

	return is_open
}

@(private)
__do_menu :: proc(is_open: bool) {
	using opal
	if is_open {
		end_node()
	}
	end_node()
}


FILLER_TEXT :: "Algo de texto que puedes seleccionar si gusta."

App :: struct {
	cursors:  [sdl3.SystemCursor]^sdl3.Cursor,
	window:   ^sdl3.Window,
	image:    int,
	run:      bool,
	platform: kn.Platform,
}

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

	hit_test_callback :: proc "c" (
		window: ^sdl3.Window,
		point: ^sdl3.Point,
		data: rawptr,
	) -> sdl3.HitTestResult {
		context = runtime.default_context()
		width, height: i32
		sdl3.GetWindowSize(window, &width, &height)
		titlebar := sdl3.Rect{0, 0, width, 30}
		opal.handle_mouse_motion(f32(point.x), f32(point.y))
		CORNER_SIZE :: 8
		if sdl3.PointInRect(point^, {0, 0, CORNER_SIZE, CORNER_SIZE}) {
			return .RESIZE_TOPLEFT
		}
		if sdl3.PointInRect(point^, {width - CORNER_SIZE, 0, CORNER_SIZE, CORNER_SIZE}) {
			return .RESIZE_TOPRIGHT
		}
		if sdl3.PointInRect(point^, {0, height - CORNER_SIZE, CORNER_SIZE, CORNER_SIZE}) {
			return .RESIZE_BOTTOMLEFT
		}
		if sdl3.PointInRect(
			point^,
			{width - CORNER_SIZE, height - CORNER_SIZE, CORNER_SIZE, CORNER_SIZE},
		) {
			return .RESIZE_BOTTOMRIGHT
		}
		SIZE :: 3
		if sdl3.PointInRect(point^, {0, 0, SIZE, height}) {
			return .RESIZE_LEFT
		}
		if sdl3.PointInRect(point^, {width - SIZE, 0, SIZE, height}) {
			return .RESIZE_RIGHT
		}
		if sdl3.PointInRect(point^, {0, 0, width, SIZE}) {
			return .RESIZE_TOP
		}
		if sdl3.PointInRect(point^, {0, height - SIZE, width, SIZE}) {
			return .RESIZE_BOTTOM
		}
		if !opal.global_ctx.widget_hovered && sdl3.PointInRect(point^, titlebar) {
			return .DRAGGABLE
		}
		return .NORMAL
	}


	app_main :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
		context = runtime.default_context()
		appstate^ = new_clone(App{run = true})
		app := (^App)(appstate^)

		app.window = sdl3.CreateWindow("OPAL", 800, 600, {.RESIZABLE, .BORDERLESS, .TRANSPARENT})
		sdl3.SetWindowHitTest(app.window, hit_test_callback, nil)
		sdl3.SetWindowMinimumSize(app.window, 500, 400)

		platform := sdl3glue.make_platform_sdl3glue(app.window)
		kn.start_on_platform(platform)
		lucide.load()
		opal.init()
		opal.global_ctx.callback_data = app
		opal.global_ctx.on_set_cursor = proc(cursor: opal.Cursor, data: rawptr) -> bool {
			app := (^App)(data)
			switch cursor {
			case .Normal:
				return sdl3.SetCursor(app.cursors[.DEFAULT])
			case .Pointer:
				return sdl3.SetCursor(app.cursors[.POINTER])
			case .Text:
				return sdl3.SetCursor(app.cursors[.TEXT])
			}
			return false
		}

		// Create system cursors
		for cursor in sdl3.SystemCursor {
			app.cursors[cursor] = sdl3.CreateSystemCursor(cursor)
		}

		app.image = opal.load_image("image.png") or_else panic("Could not load image!")

		return .CONTINUE
	}

	app_iter :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
		using opal
		context = runtime.default_context()
		app := (^App)(appstate)
		ctx := global_ctx

		kn.new_frame()

		begin()
		begin_node(
			{
				size = kn.get_size(),
				bg = tw.NEUTRAL_950,
				vertical = true,
				p = 1,
				stroke_width = 1,
				stroke = tw.NEUTRAL_800,
				radius = 8,
				clip = true,
			},
		)
		{
			begin_node(
				{
					h = 20,
					fit_y = true,
					max_w = math.F32_MAX,
					grow_x = true,
					bg = tw.NEUTRAL_900,
					content_align_y = 0.5,
				},
			)
			{
				begin_node({fit = true, p = 3, gap = 3})
				{
					if do_menu("File") {
						do_menu_item("New", lucide.PLUS)
						do_menu_item("Open", lucide.FOLDER_OPEN)
						do_menu_item("Save", lucide.SAVE)
						do_menu_item("Save As", lucide.SAVE)
					}
					if do_menu("Edit") {
						do_menu_item("Undo", lucide.UNDO)
						do_menu_item("Redo", lucide.REDO)
					}
					if do_menu("Select") {
						do_menu_item("All", lucide.TEXT_SELECT)
						do_menu_item("Invert", lucide.LASSO_SELECT)
					}
					if do_menu("Object") {
						do_menu_item("Create", lucide.PLUS)
						do_menu_item("Delete", lucide.TRASH)
					}
					if do_menu("Help") {
						do_menu_item("Manual", lucide.BOOK)
						do_menu_item("Forum", lucide.MESSAGE_CIRCLE)
					}
				}
				end_node()
				do_node({grow = true, max_size = math.F32_MAX})
				if do_window_button(lucide.CHEVRON_DOWN, tw.ROSE_500) {
					sdl3.MinimizeWindow(app.window)
				}
				if do_window_button(lucide.CHEVRON_UP, tw.ROSE_500) {
					if .MAXIMIZED in sdl3.GetWindowFlags(app.window) {
						sdl3.RestoreWindow(app.window)
					} else {
						sdl3.MaximizeWindow(app.window)
					}
				}
				if do_window_button(lucide.X, tw.ROSE_500) {
					app.run = false
				}
			}
			end_node()

			do_node({h = 1, grow_x = true, max_w = math.F32_MAX, bg = tw.NEUTRAL_800})

			begin_node({max_size = math.F32_MAX, grow = true})
			{
				begin_node({max_size = math.F32_MAX, grow = true, vertical = true})
				{
					begin_node(
						{
							max_h = math.F32_MAX,
							grow_y = true,
							p = 5,
							gap = 1,
							fit_x = true,
							vertical = true,
						},
					)
					{
						do_button(lucide.FOLDER_PLUS, font = &lucide.font, font_size = 20)
						do_node({h = 4})
						do_button(lucide.WAND_SPARKLES, font = &lucide.font, font_size = 20)
						do_node({h = 4})
						do_button(
							lucide.MOVE_3D,
							font = &lucide.font,
							font_size = 20,
							radius = {3, 3, 0, 0},
						)
						do_button(
							lucide.ROTATE_3D,
							font = &lucide.font,
							font_size = 20,
							radius = 0,
						)
						do_button(
							lucide.SCALE_3D,
							font = &lucide.font,
							font_size = 20,
							radius = {0, 0, 3, 3},
						)
					}
					end_node()
				}
				end_node()

				do_node({w = 1, grow_y = true, max_h = math.F32_MAX, bg = tw.NEUTRAL_800})

				begin_node(
					{
						w = 200,
						grow_y = true,
						max_h = math.F32_MAX,
						vertical = true,
						gap = 2,
						p = 10,
						// bg = Linear_Gradient {
						// 	colors = {tw.NEUTRAL_800, tw.NEUTRAL_900},
						// 	points = {0, 1},
						// },
						bg = Radial_Gradient {
							center = 0.5,
							radius = 0.5,
							inner = tw.NEUTRAL_800,
							outer = tw.NEUTRAL_900,
						},
						content_align_x = 0.5,
						content_align_y = 0.5,
					},
				)
				{
					do_node(
						{
							size = 100,
							bg = Image_Paint{index = app.image, size = 1},
							radius = 50,
							pos = {100, -50},
						},
					)
					do_node(
						{
							text = FILLER_TEXT,
							fit_y = true,
							grow_x = true,
							max_w = math.F32_MAX,
							font_size = 12,
							fg = tw.NEUTRAL_200,
							wrap = true,
							selectable = true,
							py = 10,
						},
					)
					do_button("Botón A")
					do_button("Botón B")
				}
				end_node()
			}
			end_node()
		}
		end_node()
		end()

		if ctx.is_debugging {
			kn.set_paint(kn.BLACK)
			text := kn.make_text(
				fmt.tprintf("FPS: %.0f\n%v", kn.get_fps(), ctx.compute_duration),
				12,
			)
			kn.add_box({0, text.size}, paint = kn.fade(kn.BLACK, 1.0))
			kn.add_text(text, 0, paint = kn.WHITE)
		}

		kn.set_clear_color({})
		if requires_redraw() {
			kn.present()
		}

		free_all(context.temp_allocator)

		if !app.run {
			return .SUCCESS
		}
		return .CONTINUE
	}

	app_event :: proc "c" (appstate: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
		using opal
		context = runtime.default_context()
		app := (^App)(appstate)
		#partial switch event.type {
		case .QUIT:
			app.run = false
		case .KEY_DOWN:
			if event.key.key == sdl3.K_F3 {
				global_ctx.is_debugging = !global_ctx.is_debugging
			}
		case .MOUSE_BUTTON_DOWN:
			handle_mouse_down(Mouse_Button(int(event.button.button) - 1))
		case .MOUSE_BUTTON_UP:
			handle_mouse_up(Mouse_Button(int(event.button.button) - 1))
		case .MOUSE_MOTION:
			handle_mouse_motion(event.motion.x, event.motion.y)
		case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
			handle_window_size_change(event.window.data1, event.window.data2)
		case .WINDOW_RESTORED:
			draw_frames(2)
		case .TEXT_INPUT:
			handle_text_input(event.text.text)
		}
		return .CONTINUE
	}

	app_quit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
		context = runtime.default_context()
		app := (^App)(appstate)
		// kn.destroy_platform(&app.platform)
		kn.shutdown()
		opal.deinit()
		sdl3.DestroyWindow(app.window)
		sdl3.Quit()
	}

	sdl3.EnterAppMainCallbacks(0, nil, app_main, app_iter, app_event, app_quit)
}

