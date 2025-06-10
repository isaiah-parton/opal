package components

import ".."

make_boolean :: proc(value: ^bool) -> opal.Node_Descriptor {
	using opal
	return Node_Descriptor {
		data = value,
		sizing = {fit = 1, exact = theme.base_size},
		on_draw = proc(self: ^Node) {

		},
	}
}
