package components

import "../opal"
import tw "../tailwind_colors"

Theme :: struct {
	font:            opal.Font,
	monospace_font:  opal.Font,
	icon_font:       opal.Font,
	radius_small:    f32,
	radius_big:      f32,
	color:           Colors,
	base_size:       [2]f32,
	animation_time:  f32,
	font_size_small: f32,
}


theme: Theme = {}

