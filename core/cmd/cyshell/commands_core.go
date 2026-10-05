package main

import (
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"

	"github.com/Cytech-Team/CyShell-Desktop/core/internal/config"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/log"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/server"
	"github.com/Cytech-Team/CyShell-Desktop/core/internal/utils"
	"github.com/spf13/cobra"
)

var coreCmd = &cobra.Command{
	Use:   "core",
	Short: "Run the CyShell backend runtime without a UI process",
	Long:  "Run only the CyShell backend/runtime. UI roles connect independently and may restart without restarting this process.",
	Args:  cobra.NoArgs,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runCoreOnly()
	},
}

type coreSocketProxy struct {
	path   string
	target string
	ln     *net.UnixListener
	wg     sync.WaitGroup
}

func runCoreOnly() error {
	config.CleanupStrayHyprlandConfFile(log.Infof)
	server.CLIVersion = Version

	srv := server.New()
	if err := srv.Listen(); err != nil {
		return fmt.Errorf("listen CyShell core: %w", err)
	}
	defer srv.Close()

	socketPath := srv.SocketPath()
	proxy, err := startCoreSocketProxy(socketPath)
	if err != nil {
		return fmt.Errorf("start stable CyShell socket: %w", err)
	}
	defer proxy.Close()

	log.Infof("CyShell core ready (ipc=%s stable=%s)", socketPath, proxy.path)

	done := make(chan error, 1)
	go func() {
		done <- srv.Serve(false)
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(sigChan)

	select {
	case sig := <-sigChan:
		log.Infof("CyShell core received %v, shutting down", sig)
		srv.Close()
		return nil
	case err := <-done:
		if err != nil {
			return fmt.Errorf("CyShell core exited: %w", err)
		}
		return nil
	}
}

func coreSocketAliasPath() string {
	return filepath.Join(utils.RuntimeDir(), "cyshell-current.sock")
}

func startCoreSocketProxy(target string) (*coreSocketProxy, error) {
	path := coreSocketAliasPath()
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}

	addr := &net.UnixAddr{Name: path, Net: "unix"}
	ln, err := net.ListenUnix("unix", addr)
	if err != nil {
		return nil, err
	}
	if err := os.Chmod(path, 0o600); err != nil {
		ln.Close()
		_ = os.Remove(path)
		return nil, err
	}

	proxy := &coreSocketProxy{path: path, target: target, ln: ln}
	proxy.wg.Add(1)
	go proxy.acceptLoop()
	return proxy, nil
}

func (p *coreSocketProxy) acceptLoop() {
	defer p.wg.Done()
	for {
		client, err := p.ln.AcceptUnix()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			log.Warnf("stable CyShell socket accept failed: %v", err)
			continue
		}

		p.wg.Add(1)
		go func() {
			defer p.wg.Done()
			p.forward(client)
		}()
	}
}

func (p *coreSocketProxy) forward(client *net.UnixConn) {
	defer client.Close()

	backend, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: p.target, Net: "unix"})
	if err != nil {
		log.Debugf("stable CyShell socket backend dial failed: %v", err)
		return
	}
	defer backend.Close()

	var copies sync.WaitGroup
	copies.Add(2)
	go func() {
		defer copies.Done()
		_, _ = io.Copy(backend, client)
		_ = backend.CloseWrite()
	}()
	go func() {
		defer copies.Done()
		_, _ = io.Copy(client, backend)
		_ = client.CloseWrite()
	}()
	copies.Wait()
}

func (p *coreSocketProxy) Close() {
	if p == nil {
		return
	}
	_ = p.ln.Close()
	p.wg.Wait()
	_ = os.Remove(p.path)
}
