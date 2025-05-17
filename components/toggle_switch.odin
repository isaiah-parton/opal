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
	self := add_node(
		&{
			size = {35, 20},
			radius = 10,
			background = tw.NEUTRAL_950,
			stroke = tw.BLUE_800,
			stroke_type = .Outer,
			on_draw = proc(self: ^Node) {
				using opal
				inner_box := box_shrink(self.box, 2)
				thumb_size := box_height(inner_box)
				travel := box_width(inner_box) - thumb_size
				thumb_box := Box {
					{
						inner_box.lo.x + travel * ease.cubic_in_out(self.transitions[0]),
						inner_box.lo.y,
					},
					{},
				}
				thumb_box.hi = thumb_box.lo + thumb_size
				kn.add_box(
					{self.box.lo, {thumb_box.hi.x + 2, self.box.hi.y}},
					box_height(self.box) / 2,
					paint = fade(tw.BLUE_500, self.transitions[0]),
				)
				kn.add_box(thumb_box, thumb_size / 2, paint = tw.WHITE)
			},
		},
	).?
	if self.is_hovered && self.was_active && !self.is_active {
		value^ = !value^
	}
	node_update_transition(self, 0, value^, 0.2)
	node_update_transition(self, 1, self.is_active, 0.1)
	self.style.stroke_width = 3 * self.transitions[1]
}
