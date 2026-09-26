package cycom

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

type assistantHistoryFile struct {
	Version  int                  `json:"version"`
	Messages []ChatHistoryMessage `json:"messages"`
}

func assistantHistoryPath(manager *Manager) string {
	if manager != nil && manager.runtime != nil && manager.runtime.StateDir() != "" {
		return filepath.Join(manager.runtime.StateDir(), "cyshell-assistant-history.json")
	}
	return filepath.Join(defaultStateDir(), "cyshell-assistant-history.json")
}

func (a *Assistant) loadHistory() error {
	if a == nil || a.historyPath == "" {
		return nil
	}
	data, err := os.ReadFile(a.historyPath)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var file assistantHistoryFile
	if err := json.Unmarshal(data, &file); err != nil {
		return errors.New("decode Assistant history: " + err.Error())
	}
	messages := make([]ChatHistoryMessage, 0, len(file.Messages))
	for _, item := range file.Messages {
		if item.Role != "user" && item.Role != "assistant" {
			continue
		}
		if item.Content == "" {
			continue
		}
		messages = append(messages, item)
	}
	if len(messages) > assistantMaxTurns*2 {
		messages = append([]ChatHistoryMessage(nil), messages[len(messages)-assistantMaxTurns*2:]...)
	}
	a.history = messages
	return nil
}

func (a *Assistant) persistHistoryLocked() error {
	if a == nil || a.historyPath == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(a.historyPath), 0o700); err != nil {
		return err
	}
	data, err := json.MarshalIndent(assistantHistoryFile{
		Version:  1,
		Messages: a.history,
	}, "", "  ")
	if err != nil {
		return err
	}
	tmp := a.historyPath + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o600); err != nil {
		return err
	}
	if err := os.Chmod(tmp, 0o600); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, a.historyPath)
}
