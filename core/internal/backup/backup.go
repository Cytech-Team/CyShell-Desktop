package backup

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	dirName       = "CyShell"
	legacyDirName = "DankMaterialShell"
)

func ConfigDir() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	primary := filepath.Join(configDir, dirName)
	if _, err := os.Stat(primary); err == nil {
		return primary, nil
	}
	legacy := filepath.Join(configDir, legacyDirName)
	if _, err := os.Stat(legacy); err == nil {
		return legacy, nil
	}
	return primary, nil
}

func DefaultArchiveName() string {
	return fmt.Sprintf("cyshell-backup-%s.tar.gz", time.Now().Format("20060102-150405"))
}

func Create(outputPath string) error {
	srcDir, err := ConfigDir()
	if err != nil {
		return err
	}
	if _, err := os.Stat(srcDir); err != nil {
		return fmt.Errorf("no CyShell configuration found at %s: %w", srcDir, err)
	}

	out, err := os.Create(outputPath)
	if err != nil {
		return err
	}
	defer out.Close()

	gz := gzip.NewWriter(out)
	defer gz.Close()
	tw := tar.NewWriter(gz)
	defer tw.Close()

	return filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(srcDir, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		var link string
		if info.Mode()&os.ModeSymlink != 0 {
			if link, err = os.Readlink(path); err != nil {
				return err
			}
		}
		header, err := tar.FileInfoHeader(info, link)
		if err != nil {
			return err
		}
		header.Name = filepath.ToSlash(filepath.Join(dirName, rel))
		if err := tw.WriteHeader(header); err != nil {
			return err
		}
		if !info.Mode().IsRegular() {
			return nil
		}
		f, err := os.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		_, err = io.Copy(tw, f)
		return err
	})
}

func Restore(archivePath string) (string, error) {
	configRoot, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	dstDir := filepath.Join(configRoot, dirName)
	if err := validateArchive(archivePath); err != nil {
		return "", err
	}

	previous := ""
	if _, err := os.Stat(dstDir); err == nil {
		previous = dstDir + ".pre-restore-" + time.Now().Format("20060102-150405")
		if err := os.Rename(dstDir, previous); err != nil {
			return "", fmt.Errorf("failed to move existing configuration aside: %w", err)
		}
	}

	if err := extract(archivePath, configRoot); err != nil {
		if previous != "" {
			os.RemoveAll(dstDir)
			_ = os.Rename(previous, dstDir)
		}
		return "", err
	}
	return previous, nil
}

func archiveRelativePath(name string) (string, bool) {
	clean := filepath.ToSlash(filepath.Clean(name))
	if strings.HasPrefix(clean, "..") || filepath.IsAbs(name) {
		return "", false
	}
	for _, root := range []string{dirName, legacyDirName} {
		if clean == root {
			return "", true
		}
		prefix := root + "/"
		if strings.HasPrefix(clean, prefix) {
			return strings.TrimPrefix(clean, prefix), true
		}
	}
	return "", false
}

func validateArchive(archivePath string) error {
	hasSettings := false
	err := walkArchive(archivePath, func(header *tar.Header, _ *tar.Reader) error {
		rel, ok := archiveRelativePath(header.Name)
		if !ok {
			return fmt.Errorf("not a CyShell backup: unexpected entry %s", header.Name)
		}
		if rel == "settings.json" {
			hasSettings = true
		}
		return nil
	})
	if err != nil {
		return err
	}
	if !hasSettings {
		return fmt.Errorf("not a CyShell backup: settings.json missing from archive")
	}
	return nil
}

func extract(archivePath, destParent string) error {
	return walkArchive(archivePath, func(header *tar.Header, tr *tar.Reader) error {
		rel, ok := archiveRelativePath(header.Name)
		if !ok {
			return fmt.Errorf("unsafe or unsupported path in archive: %s", header.Name)
		}
		if rel == "" {
			return nil
		}
		target := filepath.Join(destParent, dirName, filepath.FromSlash(rel))
		if !strings.HasPrefix(filepath.Clean(target), filepath.Clean(filepath.Join(destParent, dirName))+string(os.PathSeparator)) {
			return fmt.Errorf("unsafe path in archive: %s", header.Name)
		}
		switch header.Typeflag {
		case tar.TypeDir:
			return os.MkdirAll(target, os.FileMode(header.Mode))
		case tar.TypeSymlink:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			return os.Symlink(header.Linkname, target)
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			f, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, os.FileMode(header.Mode))
			if err != nil {
				return err
			}
			defer f.Close()
			_, err = io.Copy(f, tr)
			return err
		default:
			return nil
		}
	})
}

func walkArchive(archivePath string, visit func(*tar.Header, *tar.Reader) error) error {
	f, err := os.Open(archivePath)
	if err != nil {
		return err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("not a gzip archive: %w", err)
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		header, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if err := visit(header, tr); err != nil {
			return err
		}
	}
}
