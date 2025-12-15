package components

import ".."
import tw "../tailwind_colors"
import "base:intrinsics"
import "core:fmt"
import "core:math"

Slider_Descriptor :: struct($T: typeid) where intrinsics.type_is_numeric(T) {
	using base: opal.Node_Descriptor,
	min:        T,
	max:        T,
	value:      T,
}

Slider_Response :: struct($T: typeid) {
	node:      opal.Node_Result,
	new_value: Maybe(T),
}

add_slider :: proc(
	desc: ^Slider_Descriptor($T),
	loc := #caller_location,
) -> (
	res: Slider_Response(T),
) {
	using opal

	push_id(hash(loc))
	defer pop_id()

	desc.sizing.exact.x = max(desc.sizing.exact.x, 100)
	desc.sizing.exact.y = theme.base_size.y * 2
	radius := desc.sizing.exact.y / 4
	desc.interactive = true
	desc.sticky = true
	desc.group = true
	desc.padding = desc.sizing.exact.y * [4]f32{0, 0.25, 0, 0.25}

	body_node := begin_node(desc).?
	time: f32 = clamp(f32(desc.value) / f32(desc.max - desc.min), 0.0, 1.0)

	// node_update_transition(body_node, 0, body_node.is_hovered, 0.1)
	node_update_transition(body_node, 1, body_node.is_active, 0.1)

	begin_node(
		&{
			sizing = {grow = 1, max = INFINITY},
			group = true,
			padding = theme.base_size.y * [4]f32{0.5, 0.25, 0.5, 0.25},
			background = tw.NEUTRAL_950,
			radius = radius,
		},
	)
	add_node(
		&{
			absolute = true,
			sizing = {relative = {time, 1}, exact = {radius * (1 - 2 * time), 0}},
			radius = {radius, 0, radius, 0},
			background = theme.color.secondary,
		},
	)
	begin_node(&{sizing = {grow = 1, max = INFINITY}})

	thumb_size := desc.sizing.exact.y * (1 - body_node.transitions[1] * 0.15)
	add_node(
		&{
			absolute = true,
			relative_offset = {time, 0.5},
			align = 0.5,
			sizing = {exact = thumb_size},
			radius = thumb_size / 2,
			background = theme.color.secondary_strong,
			shadow_size = 4,
			shadow_offset = {-1, 2},
			shadow_color = fade(tw.BLACK, 0.5),
		},
	)

	end_node()
	end_node()
	end_node()

	if body_node.is_active {
		new_time := clamp(
			(global_ctx.mouse_position.x - body_node.box.lo.x) / body_node.size.x,
			0,
			1,
		)
		res.new_value = T(math.lerp(f64(desc.min), f64(desc.max), f64(new_time)))
	}

	res.node = body_node

	return
}

