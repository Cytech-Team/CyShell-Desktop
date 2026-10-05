package keybinds

import "github.com/Cytech-Team/CyShell-Desktop/core/internal/configfrag"

type Keybind struct {
	Key             string   `json:"key"`
	Description     string   `json:"desc"`
	Action          string   `json:"action,omitempty"`
	Subcategory     string   `json:"subcat,omitempty"`
	Source          string   `json:"source,omitempty"`
	HideOnOverlay   bool     `json:"hideOnOverlay,omitempty"`
	CooldownMs      int      `json:"cooldownMs,omitempty"`
	Flags           string   `json:"flags,omitempty"` // Hyprland bind flags: e=repeat, l=locked, r=release, o=long-press
	AllowWhenLocked bool     `json:"allowWhenLocked,omitempty"`
	AllowInhibiting *bool    `json:"allowInhibiting,omitempty"` // nil=default(true), false=explicitly disabled
	Repeat          *bool    `json:"repeat,omitempty"`          // nil=default(true), false=explicitly disabled
	Conflict        *Keybind `json:"conflict,omitempty"`
	HasDefault      bool     `json:"hasDefault,omitempty"` // override has a CyShell default to revert to
}

type CyShellBindsStatus struct {
	Exists            bool   `json:"exists"`
	Included          bool   `json:"included"`
	IncludePosition   int    `json:"includePosition"`
	TotalIncludes     int    `json:"totalIncludes"`
	BindsAfterCyShell int    `json:"bindsAfterCyShell"`
	Effective         bool   `json:"effective"`
	OverriddenBy      int    `json:"overriddenBy"`
	StatusMessage     string `json:"statusMessage"`
	ConfigFormat      string `json:"configFormat,omitempty"`
	ReadOnly          bool   `json:"readOnly,omitempty"`
}

type CheatSheet struct {
	Generation           string               `json:"generation,omitempty"`
	Title                string               `json:"title"`
	Provider             string               `json:"provider"`
	ModKey               string               `json:"modKey,omitempty"`
	Binds                map[string][]Keybind `json:"binds"`
	ManagedOverrideCount int                  `json:"managedOverrideCount,omitempty"`
	CyShellBindsIncluded bool                 `json:"cyShellBindsIncluded"`
	CyShellStatus        *CyShellBindsStatus  `json:"cyShellStatus,omitempty"`
}

type Provider interface {
	Name() string
	GetCheatSheet() (*CheatSheet, error)
}

type WritableProvider interface {
	Provider
	SetBind(key, action, description string, options map[string]any) error
	// RemoveBind removes the bind. Hyprland writes a negative override to
	// cyshell/binds-user.lua; single-file providers delete the line.
	RemoveBind(key string) error
	// ResetBind reverts a user override to its CyShell default. On single-file
	// providers this aliases to RemoveBind.
	ResetBind(key string) error
	GetOverridePath() string
}

type BulkResettableProvider interface {
	WritableProvider
	ResetAllManagedBinds() (int, error)
}

// ReplacingProvider can atomically move a binding while preserving provider-
// specific override semantics. Providers that do not implement it fall back to
// RemoveBind followed by SetBind.
type ReplacingProvider interface {
	WritableProvider
	ReplaceBind(originalKey, key, action, description string, options map[string]any) error
}

func CyShellBindsStatusFrom(s configfrag.Status) *CyShellBindsStatus {
	return &CyShellBindsStatus{
		Exists:            s.Exists,
		Included:          s.Included,
		IncludePosition:   s.IncludePosition,
		TotalIncludes:     s.TotalIncludes,
		BindsAfterCyShell: s.EntriesAfterCyShell,
		Effective:         s.Effective,
		OverriddenBy:      s.OverriddenBy,
		StatusMessage:     s.StatusMessage,
		ConfigFormat:      s.ConfigFormat,
		ReadOnly:          s.ReadOnly,
	}
}
