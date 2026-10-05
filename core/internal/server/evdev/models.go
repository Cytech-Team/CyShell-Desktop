package evdev

type State struct {
	Available          bool   `json:"available"`
	CapsLock           bool   `json:"capsLock"`
	LayoutToggleSerial uint64 `json:"layoutToggleSerial"`
	AltTabSerial       uint64 `json:"altTabSerial"`
	AltTabReverse      bool   `json:"altTabReverse"`
}
