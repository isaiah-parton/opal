package components

import ".."

make_boolean :: proc(value: ^bool) -> opal.Node_Descriptor {
	using opal
	return Node_Descriptor {
		data = value,
		size = theme.base_size,
		fit = 1,
		on_draw = proc(self: ^Node) {

		},
	}
}

