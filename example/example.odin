package example

import opal ".."
import kn "../../katana"
import "../../katana/sdl3glue"
import "../lucide"
import "../sdl3app"
import tw "../tailwind_colors"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
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
			padding = 3,
			fit = 1,
			text = string_from_rune(icon),
			font_size = 20,
			fg = tw.NEUTRAL_300,
			font = &lucide.font,
			max_size = INFINITY,
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
			padding = 3,
			radius = radius,
			fit = 1,
			text = label.(string) or_else string_from_rune(label.(rune)),
			font_size = font_size,
			fg = tw.NEUTRAL_300,
			font = font,
			max_size = INFINITY,
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
		padding = {3, 3, 12, 3},
		radius = 3,
		fit = 1,
		spacing = 6,
		max_size = INFINITY,
		grow = {true, false},
		content_align = {0, 0.5},
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
			fit = 1,
			fg = tw.NEUTRAL_300,
		},
	)
	do_node({text = label, font_size = 12, fit = 1, fg = tw.NEUTRAL_300})
	end_node()
	pop_id()
}

@(deferred_out = __do_menu)
do_menu :: proc(label: string, loc := #caller_location) -> bool {
	using opal
	push_id(hash(loc))
	node := begin_node({
		padding = 3,
		radius = 3,
		fit = 1,
		text = label,
		font_size = 12,
		fg = tw.NEUTRAL_300,
		widget = true,
		on_animate = proc(self: ^Node) {
			self.style.background_paint = kn.fade(
				tw.NEUTRAL_600,
				(self.transitions[0] + self.transitions[1]) * 0.3,
			)
			node_update_transition(self, 1, self.is_active, 0)
			node_update_transition(self, 0, self.is_hovered, 0)
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
				absolute = true,
				relative_pos = {0, 1},
				position = {0, 4},
				fit = 1,
				padding = 3,
				spacing = 3,
				radius = 3,
				bg = tw.NEUTRAL_900,
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

My_App :: struct {
	using app:             sdl3app.App,
	image:                 int,
	edited_text:           string,
	inspector_position:    [2]f32,
	drag_offset:           [2]f32,
	is_dragging_inspector: bool,
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

	sdl3app.state = new_clone(My_App {
		run = true,
		on_start = proc(app: ^sdl3app.App) {
			app := (^My_App)(app)
			lucide.load()
			app.image = opal.load_image("image.png") or_else panic("Could not load image!")
		},
		on_frame = proc(app: ^sdl3app.App) {
			app := (^My_App)(app)
			using opal
			begin()
			begin_node(
				{
					size = kn.get_size(),
					bg = tw.NEUTRAL_950,
					vertical = true,
					padding = 1,
					stroke_width = 1,
					stroke = tw.NEUTRAL_600,
				},
			)
			{
				begin_node(
					{
						size = {0, 20},
						max_size = INFINITY,
						fit = {0, 1},
						grow = {true, false},
						content_align = {0, 0.5},
						bg = tw.NEUTRAL_900,
					},
				)
				{
					begin_node({fit = 1, padding = 3, spacing = 3})
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
					do_node({grow = true, max_size = INFINITY})
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

				do_node(
					{
						size = {0, 1},
						grow = {true, false},
						max_size = INFINITY,
						bg = tw.NEUTRAL_600,
					},
				)

				begin_node({max_size = INFINITY, grow = true})
				{
					begin_node({max_size = INFINITY, grow = true, vertical = true})
					{
						begin_node(
							{
								max_size = INFINITY,
								grow = {false, true},
								fit = {1, 0},
								padding = 5,
								spacing = 1,
								vertical = true,
							},
						)
						{
							do_button(lucide.FOLDER_PLUS, font = &lucide.font, font_size = 20)
							do_node({size = {0, 4}})
							do_button(lucide.WAND_SPARKLES, font = &lucide.font, font_size = 20)
							do_node({size = {0, 4}})
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

					do_node(
						{
							size = {1, 0},
							grow = {false, true},
							max_size = INFINITY,
							bg = tw.NEUTRAL_600,
						},
					)

					begin_node(
						{
							size = {200, 0},
							grow = {false, true},
							max_size = INFINITY,
							vertical = true,
							spacing = 2,
							padding = 10,
							bg = Radial_Gradient {
								center = {1, 0.5},
								radius = 0.5,
								inner = tw.NEUTRAL_800,
								outer = tw.NEUTRAL_900,
							},
							content_align = 0.5,
						},
					)
					{
						do_node(
							{
								size = 100,
								bg = Image_Paint{index = app.image, size = 1},
								radius = 50,
							},
						)
						do_node(
							{
								text = FILLER_TEXT,
								fit = {0, 1},
								grow = {true, false},
								max_size = INFINITY,
								font_size = 12,
								fg = tw.NEUTRAL_200,
								wrap = true,
								selectable = true,
								padding = {0, 10, 0, 10},
							},
						)
						do_button("Botón A")
						do_button("Botón B")
						node := do_node({
							bg = tw.NEUTRAL_950,
							stroke = tw.NEUTRAL_500,
							stroke_width = 1,
							clip = true,
							text = app.edited_text,
							font_size = 12,
							padding = 4,
							radius = 3,
							fg = tw.NEUTRAL_50,
							fit = {0, 1},
							max_size = INFINITY,
							grow = {true, false},
							editable = true,
							selectable = true,
							widget = true,
							stroke_type = .Outer_Stroke,
							on_animate = proc(self: ^Node) {
								self.style.stroke_paint = tw.LIME_500
								self.style.stroke_width = 3 * self.transitions[1]
								self.transitions[1] +=
									(f32(i32(self.is_focused)) - self.transitions[1]) *
									rate_per_second(14)
								self.transitions[0] +=
									(f32(i32(self.is_hovered)) - self.transitions[0]) *
									rate_per_second(14)
							},
						})
						if node.was_changed {
							delete(app.edited_text)
							app.edited_text = strings.clone(strings.to_string(node.builder))
						}
					}
					end_node()
				}
				end_node()
			}
			end_node()
			inspector_show(&global_ctx.inspector)
			end()
		},
	})

	sdl3app.run()
}

