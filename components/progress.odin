package components

import ".."
import kn "../../katana"
import "core:math"

Radial_Progress_Descriptor :: struct {
	base:  opal.Node_Descriptor,
	time:  f32,
	size:  f32,
	color: Maybe(opal.Color),
}

add_radial_progress :: proc(desc: ^Radial_Progress_Descriptor, loc := #caller_location) {
	using opal
	assert(desc != nil)
	desc.base.foreground = desc.color.? or_else theme.color.accent
	desc.base.radius[0] = desc.time
	desc.base.min_size = desc.size
	desc.base.on_draw = proc(self: ^Node) {
		using opal
		center := box_center(self.box)
		radius := box_width(self.box) / 2
		kn.add_arc(
			center,
			math.PI * 0.75,
			math.PI * 2.25,
			radius - 10,
			radius,
			true,
			paint = theme.color.base_strong,
		)
		kn.add_arc(
			center,
			math.PI * 0.75,
			math.PI * (0.75 + 1.5 * self.radius[0]),
			radius - 10,
			radius,
			true,
			paint = self.foreground.(Color),
		)
	}
	add_node(&desc.base)
}

