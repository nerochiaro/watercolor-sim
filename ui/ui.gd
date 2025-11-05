extends CanvasLayer

@export var drop_size: int:
	get:
		return %DropSizeSlider.value

@export var drop_wetness: int:
	get:
		return %DropWetnessSlider.value

@export var pigment_drop_size: int:
	get:
		return %PigmentDropSizeSlider.value

@export var pigment_drop_wetness: int:
	get:
		return %PigmentDropWetnessSlider.value

@export var dry_rate: int:
	get:
		return %DryRateSlider.value

func _ready():
	%DropSizeSlider.value = drop_size
	%DropSizeSlider.value_changed.connect(on_drop_size_changed)
	on_drop_size_changed(%DropSizeSlider.value)
	%DropWetnessSlider.value_changed.connect(on_drop_wetness_changed)
	%DropWetnessLabel.text = str(%DropWetnessSlider.value)
	%PigmentDropSizeSlider.value_changed.connect(on_pigment_drop_size_changed)
	%PigmentDropWetnessSlider.value_changed.connect(on_pigment_drop_wetness_changed)
	%PigmentDropWetnessLabel.text = str(%PigmentDropWetnessSlider.value)
	%DryRateSlider.value_changed.connect(on_dry_rate_changed)
	%DryRateLabel.text = str(%DryRateSlider.value)

func on_drop_size_changed(value: float):
	%DropSizeLabel.text = str(int(value))

func on_drop_wetness_changed(value: float):
	%DropWetnessLabel.text = str(value)

func on_pigment_drop_size_changed(value: float):
	%PigmentDropSizeLabel.text = str(int(value))

func on_pigment_drop_wetness_changed(value: float):
	%PigmentDropWetnessLabel.text = str(value)

func on_dry_rate_changed(value: float):
	%DryRateLabel.text = str(value)
