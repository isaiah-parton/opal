package example

import opal ".."
import kn "../../katana"
import "../../katana/sdl3glue"
import "../lucide"
import tw "../tailwind_colors"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:time"
import "vendor:sdl3"

do_button :: proc(label: union #no_nil {
		string,
		rune,
	}, font: ^kn.Font = nil, font_size: f32 = 12, loc := #caller_location) {
	using opal
	do_node({
			p = 3,
			radius = 3,
			fit = true,
			text = label.(string) or_else string_from_rune(label.(rune)),
			font_size = font_size,
			fg = tw.NEUTRAL_300,
			font = font,
			max_size = math.F32_MAX,
			on_animate = proc(self: ^Node) {
				self.style.background_paint = kn.fade(
					tw.NEUTRAL_600,
					0.3 + self.transitions[0] * 0.3,
				)
				self.transitions[1] +=
					(f32(i32(self.is_active)) - self.transitions[1]) * rate_per_second(7)
				self.transitions[0] +=
					(f32(i32(self.is_hovered)) - self.transitions[0]) * rate_per_second(14)
			},
		}, loc = loc)
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
		on_animate = proc(self: ^Node) {
			self.style.background_paint = kn.fade(tw.NEUTRAL_600, 0.3 + self.transitions[0] * 0.3)
			self.transitions[1] +=
				(f32(i32(self.is_active)) - self.transitions[1]) * rate_per_second(7)
			self.transitions[0] +=
				(f32(i32(self.is_hovered)) - self.transitions[0]) * rate_per_second(14)
			if self.is_hovered {
				set_cursor(.Pointer)
				if self.parent != nil && self.parent.has_focused_child {
					focus_node(self.id)
				}
			}
		},
	})

	assert(node != nil)

	is_open := node.is_focused || node.has_focused_child

	if is_open {
		begin_node(
			{
				shadow_size = 3,
				shadow_color = kn.BLACK,
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

cursors: [sdl3.SystemCursor]^sdl3.Cursor

FILLER_TEXT :: "Algo de texto que puedes seleccionar si gusta."

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

	lucide.load()

	using opal

	init()
	defer deinit()

	ctx := global_ctx

	image := load_image("image.png") or_else panic("Could not load image!")

	// Create system cursors
	for cursor in sdl3.SystemCursor {
		cursors[cursor] = sdl3.CreateSystemCursor(cursor)
	}

	// Set cursor callback
	ctx.on_set_cursor = proc(cursor: Cursor) -> bool {
		switch cursor {
		case .Normal:
			return sdl3.SetCursor(cursors[.DEFAULT])
		case .Pointer:
			return sdl3.SetCursor(cursors[.POINTER])
		case .Text:
			return sdl3.SetCursor(cursors[.TEXT])
		}
		return false
	}

	loop: for {
		event: sdl3.Event
		for sdl3.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break loop
			case .KEY_DOWN:
				if event.key.key == sdl3.K_F3 {
					ctx.is_debugging = !ctx.is_debugging
				}
			case .MOUSE_BUTTON_DOWN:
				handle_mouse_down(Mouse_Button(int(event.button.button) - 1))
			case .MOUSE_BUTTON_UP:
				handle_mouse_up(Mouse_Button(int(event.button.button) - 1))
			case .MOUSE_MOTION:
				handle_mouse_motion(event.motion.x, event.motion.y)

			case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
				kn.set_size(event.window.data1, event.window.data2)
			case .TEXT_INPUT:
				handle_text_input(event.text.text)
			}
		}

		kn.new_frame()

		begin()
		begin_node({size = kn.get_size(), bg = tw.NEUTRAL_950, vertical = true})
		{
			begin_node(
				{
					h = 20,
					fit_y = true,
					max_w = math.F32_MAX,
					grow_x = true,
					p = 3,
					gap = 3,
					bg = tw.NEUTRAL_900,
				},
			)
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
				do_node({grow = true, max_size = math.F32_MAX})
				if do_menu("Help") {
					do_menu_item("Manual", lucide.BOOK)
					do_menu_item("Forum", lucide.MESSAGE_CIRCLE)
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
							p = 3,
							gap = 3,
							fit_x = true,
							vertical = true,
						},
					)
					{
						do_button(lucide.CIRCLE_PLUS, font = &lucide.font, font_size = 20)
						do_node({w = 4})
						do_button(lucide.ZAP, font = &lucide.font, font_size = 20)
						do_node({w = 4})
						do_button(lucide.MOVE_3D, font = &lucide.font, font_size = 20)
						do_button(lucide.ROTATE_3D, font = &lucide.font, font_size = 20)
						do_button(lucide.SCALE_3D, font = &lucide.font, font_size = 20)
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
						p = 2,
						bg = tw.NEUTRAL_900,
						content_align_x = 0.5,
						content_align_y = 0.5,
					},
				)
				{
					do_node(
						{
							size = 100,
							bg = Image_Paint{index = image, size = 1},
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
				fmt.tprintf(
					"FPS: %.0f\n%.0f\n%v",
					kn.get_fps(),
					ctx.mouse_position,
					ctx.compute_duration,
				),
				12,
			)
			kn.add_box({0, text.size}, paint = kn.fade(kn.BLACK, 1.0))
			kn.add_text(text, 0, paint = kn.WHITE)
		}

		kn.set_clear_color(kn.WHITE)
		if requires_redraw() {
			kn.present()
		}

		free_all(context.temp_allocator)
	}
}

