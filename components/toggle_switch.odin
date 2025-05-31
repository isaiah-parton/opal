package components

import ".."
import kn "../../katana"
import tw "../tailwind_colors"
import "core:math/ease"

//
// **Make a node descriptor for a toggle switch**
//
// `value` must still be valid when `end()` is called
//
add_toggle_switch :: proc(value: ^bool) {
	using opal
	base_size := [2]f32{45, 25}
	self := begin_node(
		&{
			min_size    = base_size,
			radius      = base_size.y / 2,
			background  = tw.NEUTRAL_950,
			stroke      = fade(tw.WHITE, 0.1),
			stroke_type = .Outer,
			interactive = true,
			// on_draw = proc(self: ^Node) {
			// 	using opal
			// 	inner_box := box_shrink(self.box, 2)
			// 	thumb_size := box_height(inner_box)
			// 	travel := box_width(inner_box) - thumb_size
			// 	thumb_box := Box {
			// 		{
			// 			inner_box.lo.x + travel * ease.cubic_in_out(self.transitions[0]),
			// 			inner_box.lo.y,
			// 		},
			// 		{},
			// 	}
			// 	thumb_box.hi = thumb_box.lo + thumb_size
			// 	kn.add_box(
			// 		{self.box.lo, {thumb_box.hi.x + 2, self.box.hi.y}},
			// 		box_height(self.box) / 2,
			// 		paint = fade(tw.BLUE_500, self.transitions[0]),
			// 	)
			// 	kn.add_box(thumb_box, thumb_size / 2, paint = tw.WHITE)
			// },
		},
	).?
	begin_node(
		&{
			absolute = true,
			relative_offset = {self.transitions[0], 0},
			exact_offset = {-base_size.y * self.transitions[0], 0},
			min_size = base_size.y,
			padding = 2,
		},
	)
	add_node(
		&{
			max_size = INFINITY,
			grow = true,
			radius = (base_size.y - 4) / 2,
			shadow_offset = {-2, 2},
			shadow_size = 4,
			shadow_color = fade(kn.BLACK, 0.5),
			background = tw.WHITE,
			stroke = fade(tw.NEUTRAL_400, self.transitions[0]),
			stroke_width = 1,
			stroke_type = .Inner,
		},
	)
	end_node()
	end_node()

	if self.is_hovered && self.was_active && !self.is_active {
		value^ = !value^
	}
	node_update_transition(self, 0, value^, 0.2)
	node_update_transition(self, 1, self.is_active, 0.1)
	self.style.background = mix(self.transitions[0], tw.NEUTRAL_950, tw.WHITE)
	self.style.stroke_width = 4 * self.transitions[1]
}

