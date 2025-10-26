extends CanvasLayer

signal drop_size_changed(value: float)
signal drop_wetness_changed(value: float)
signal dry_rate_changed(value: float)

func _ready():
	%DropSizeSlider.value_changed.connect(on_drop_size_changed)
	%DropWetnessSlider.value_changed.connect(on_drop_wetness_changed)
	%DropWetnessLabel.text = str(%DropWetnessSlider.value)
	%DryRateSlider.value_changed.connect(on_dry_rate_changed)
	%DryRateLabel.text = str(%DryRateSlider.value)

func on_drop_size_changed(value: float):
	drop_size_changed.emit(value)
	%DropSizeLabel.text = str(int(value))

func on_drop_wetness_changed(value: float):
	drop_wetness_changed.emit(value)
	%DropWetnessLabel.text = str(value)

func on_dry_rate_changed(value: float):
	dry_rate_changed.emit(value)
	%DryRateLabel.text = str(value)
