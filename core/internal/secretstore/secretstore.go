package secretstore

import (
	"context"
	"fmt"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	busName             = "org.freedesktop.secrets"
	servicePath         = "/org/freedesktop/secrets"
	serviceIface        = "org.freedesktop.Secret.Service"
	sessionIface        = "org.freedesktop.Secret.Session"
	collectionIface     = "org.freedesktop.Secret.Collection"
	itemIface           = "org.freedesktop.Secret.Item"
	promptIface         = "org.freedesktop.Secret.Prompt"
	defaultCollection   = "/org/freedesktop/secrets/aliases/default"
	defaultPromptTimout = 120 * time.Second
)

type Store struct {
	conn        *dbus.Conn
	service     dbus.BusObject
	sessionPath dbus.ObjectPath
}

type secretValue struct {
	Session     dbus.ObjectPath
	Parameters  []byte
	Value       []byte
	ContentType string
}

func Open() (*Store, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("connect to Secret Service session bus: %w", err)
	}
	service := conn.Object(busName, dbus.ObjectPath(servicePath))
	var sessionPath dbus.ObjectPath
	call := service.Call(serviceIface+".OpenSession", 0, "plain", dbus.MakeVariant(""))
	if call.Err != nil {
		return nil, fmt.Errorf("open Secret Service session: %w", call.Err)
	}
	if err := call.Store(new(dbus.Variant), &sessionPath); err != nil {
		return nil, fmt.Errorf("decode Secret Service session: %w", err)
	}
	return &Store{conn: conn, service: service, sessionPath: sessionPath}, nil
}

func (s *Store) Close() {
	if s == nil || s.conn == nil || s.sessionPath == "" {
		return
	}
	_ = s.conn.Object(busName, s.sessionPath).Call(sessionIface+".Close", 0).Err
}

func (s *Store) Search(attributes map[string]string) (unlocked, locked []dbus.ObjectPath, err error) {
	if s == nil || s.service == nil {
		return nil, nil, fmt.Errorf("Secret Service is not open")
	}
	call := s.service.Call(serviceIface+".SearchItems", 0, attributes)
	if call.Err != nil {
		return nil, nil, call.Err
	}
	if err := call.Store(&unlocked, &locked); err != nil {
		return nil, nil, err
	}
	return unlocked, locked, nil
}

func (s *Store) Exists(attributes map[string]string) (bool, error) {
	unlocked, locked, err := s.Search(attributes)
	if err != nil {
		return false, err
	}
	return len(unlocked)+len(locked) > 0, nil
}

func (s *Store) Get(attributes map[string]string) (string, bool, error) {
	unlocked, locked, err := s.Search(attributes)
	if err != nil {
		return "", false, err
	}
	if len(unlocked) == 0 && len(locked) > 0 {
		if err := s.unlock(locked); err != nil {
			return "", false, err
		}
		unlocked = locked
	}
	if len(unlocked) == 0 {
		return "", false, nil
	}

	item := s.conn.Object(busName, unlocked[0])
	var secret secretValue
	call := item.Call(itemIface+".GetSecret", 0, s.sessionPath)
	if call.Err != nil {
		return "", false, call.Err
	}
	if err := call.Store(&secret); err != nil {
		return "", false, err
	}
	return string(secret.Value), true, nil
}

func (s *Store) Set(attributes map[string]string, label, value string) error {
	if value == "" {
		return fmt.Errorf("secret value is empty")
	}
	if err := s.unlock([]dbus.ObjectPath{dbus.ObjectPath(defaultCollection)}); err != nil {
		return fmt.Errorf("unlock default Secret Service collection: %w", err)
	}
	props := map[string]dbus.Variant{
		itemIface + ".Label":      dbus.MakeVariant(label),
		itemIface + ".Attributes": dbus.MakeVariant(attributes),
	}
	secret := secretValue{
		Session:     s.sessionPath,
		Parameters:  []byte{},
		Value:       []byte(value),
		ContentType: "text/plain",
	}
	var itemPath, promptPath dbus.ObjectPath
	call := s.conn.Object(busName, dbus.ObjectPath(defaultCollection)).Call(collectionIface+".CreateItem", 0, props, secret, true)
	if call.Err != nil {
		return call.Err
	}
	if err := call.Store(&itemPath, &promptPath); err != nil {
		return err
	}
	if itemPath != "/" {
		return nil
	}
	if promptPath == "/" {
		return fmt.Errorf("Secret Service did not create an item")
	}
	return s.runPrompt(promptPath)
}

func (s *Store) Delete(attributes map[string]string) error {
	unlocked, locked, err := s.Search(attributes)
	if err != nil {
		return err
	}
	paths := append(unlocked, locked...)
	for _, path := range paths {
		var prompt dbus.ObjectPath
		call := s.conn.Object(busName, path).Call(itemIface+".Delete", 0)
		if call.Err != nil {
			return call.Err
		}
		if err := call.Store(&prompt); err != nil {
			return err
		}
		if prompt != "/" {
			if err := s.runPrompt(prompt); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Store) unlock(paths []dbus.ObjectPath) error {
	if len(paths) == 0 {
		return nil
	}
	var unlocked []dbus.ObjectPath
	var prompt dbus.ObjectPath
	call := s.service.Call(serviceIface+".Unlock", 0, paths)
	if call.Err != nil {
		return call.Err
	}
	if err := call.Store(&unlocked, &prompt); err != nil {
		return err
	}
	if prompt == "/" {
		return nil
	}
	return s.runPrompt(prompt)
}

func (s *Store) runPrompt(prompt dbus.ObjectPath) error {
	if prompt == "" || prompt == "/" {
		return nil
	}
	if err := s.conn.AddMatchSignal(
		dbus.WithMatchInterface(promptIface),
		dbus.WithMatchObjectPath(prompt),
	); err != nil {
		return err
	}
	defer s.conn.RemoveMatchSignal(
		dbus.WithMatchInterface(promptIface),
		dbus.WithMatchObjectPath(prompt),
	)

	ctx, cancel := context.WithTimeout(context.Background(), defaultPromptTimout)
	defer cancel()
	ch := make(chan *dbus.Signal, 4)
	s.conn.Signal(ch)
	defer s.conn.RemoveSignal(ch)

	promptObj := s.conn.Object(busName, prompt)
	if call := promptObj.Call(promptIface+".Prompt", 0, ""); call.Err != nil {
		return call.Err
	}

	for {
		select {
		case signal := <-ch:
			if signal == nil || signal.Path != prompt || signal.Name != promptIface+".Completed" {
				continue
			}
			if len(signal.Body) > 0 {
				if dismissed, ok := signal.Body[0].(bool); ok && dismissed {
					return fmt.Errorf("Secret Service prompt was dismissed")
				}
			}
			return nil
		case <-ctx.Done():
			_ = promptObj.Call(promptIface+".Dismiss", 0).Err
			return fmt.Errorf("timed out waiting for Secret Service prompt")
		}
	}
}
