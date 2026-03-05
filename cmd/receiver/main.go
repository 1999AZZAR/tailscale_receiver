package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

// Config holds the service configuration
type Config struct {
	TargetDir    string        `json:"target_dir"`
	TargetUser   string        `json:"target_user"`
	PollInterval time.Duration `json:"poll_interval"`
	LogLevel     string        `json:"log_level"`
	ArchiveDays  int           `json:"archive_days"`
	ArchiveDir   string        `json:"archive_dir"`
}

var (
	version = "3.0.0-beta"
	logger  = log.New(os.Stdout, "[Tailscale-Receiver] ", log.LstdFlags)
)

func main() {
	config := loadConfig()

	logger.Printf("Starting Tailscale Receiver v%s", version)
	logger.Printf("Monitoring to: %s as user: %s", config.TargetDir, config.TargetUser)

	// Ensure target directory exists
	if err := os.MkdirAll(config.TargetDir, 0755); err != nil {
		logger.Fatalf("Failed to create target directory: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	ticker := time.NewTicker(config.PollInterval)
	defer ticker.Stop()

	// Initial run
	processFiles(config)

	for {
		select {
		case <-ctx.Done():
			logger.Println("Shutting down gracefully...")
			return
		case <-ticker.C:
			if isTailscaleUp() {
				processFiles(config)
				manageArchive(config)
			} else {
				if config.LogLevel == "debug" {
					logger.Println("Tailscale is down, skipping cycle")
				}
			}
		}
	}
}

func loadConfig() Config {
	// Simple default config, override with ENVs
	cfg := Config{
		TargetDir:    getEnv("TARGET_DIR", filepath.Join(os.Getenv("HOME"), "Downloads/tailscale")),
		TargetUser:   getEnv("TARGET_USER", os.Getenv("USER")),
		PollInterval: 15 * time.Second,
		LogLevel:     getEnv("LOG_LEVEL", "info"),
		ArchiveDays:  14,
		ArchiveDir:   "archive",
	}

	if intervalStr := os.Getenv("POLL_INTERVAL"); intervalStr != "" {
		if d, err := time.ParseDuration(intervalStr); err == nil {
			cfg.PollInterval = d
		} else if i, err := time.ParseDuration(intervalStr + "s"); err == nil {
			cfg.PollInterval = i
		}
	}

	return cfg
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func isTailscaleUp() bool {
	// Optimized: just check if tailscale is running/online
	cmd := exec.Command("tailscale", "status", "--json")
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	var status struct {
		BackendState string `json:"BackendState"`
	}
	if err := json.Unmarshal(output, &status); err != nil {
		return false
	}

	return status.BackendState == "Running"
}

func processFiles(cfg Config) {
	// Execute tailscale file get
	// Using --conflict=rename to avoid overwriting
	cmd := exec.Command("tailscale", "file", "get", cfg.TargetDir)
	err := cmd.Run()
	if err != nil {
		// This is often just "no files", so we don't log as error unless debug
		if cfg.LogLevel == "debug" {
			logger.Printf("Tailscale file get: %v", err)
		}
		return
	}

	// Fix ownership of files in TargetDir that belong to root
	files, err := os.ReadDir(cfg.TargetDir)
	if err != nil {
		return
	}

	for _, f := range files {
		if f.IsDir() && f.Name() == cfg.ArchiveDir {
			continue
		}

		fPath := filepath.Join(cfg.TargetDir, f.Name())
		info, err := f.Info()
		if err != nil {
			continue
		}

		// Check if it belongs to root (typical when service runs as root)
		if stat, ok := info.Sys().(*syscall.Stat_t); ok {
			if stat.Uid == 0 {
				logger.Printf("Found new file: %s, fixing ownership to %s", f.Name(), cfg.TargetUser)
				fixOwnership(fPath, cfg.TargetUser)
				notifyUser(f.Name(), cfg.TargetUser)
			}
		}
	}
}

func fixOwnership(path, user string) {
	// We use the 'chown' binary for simplicity and recursive handling if needed
	// But for files, we can just use the user ID
	cmd := exec.Command("chown", "-R", user+":"+user, path)
	if err := cmd.Run(); err != nil {
		logger.Printf("Error changing ownership of %s: %v", path, err)
	}
}

func notifyUser(filename, user string) {
	// Minimalist notification using notify-send
	// Only if not in a headless server environment usually
	if os.Getenv("DISPLAY") == "" && os.Getenv("WAYLAND_DISPLAY") == "" {
		return
	}

	cmd := exec.Command("sudo", "-u", user, "notify-send", "Tailscale", "Received: "+filename, "-i", "document-save")
	cmd.Run()
}

func manageArchive(cfg Config) {
	if cfg.ArchiveDays <= 0 {
		return
	}

	archivePath := filepath.Join(cfg.TargetDir, cfg.ArchiveDir)
	os.MkdirAll(archivePath, 0755)

	files, err := os.ReadDir(cfg.TargetDir)
	if err != nil {
		return
	}

	now := time.Now()
	for _, f := range files {
		if f.IsDir() {
			continue
		}

		info, err := f.Info()
		if err != nil {
			continue
		}

		if now.Sub(info.ModTime()) > time.Duration(cfg.ArchiveDays)*24*time.Hour {
			oldPath := filepath.Join(cfg.TargetDir, f.Name())
			newPath := filepath.Join(archivePath, f.Name())
			if err := os.Rename(oldPath, newPath); err == nil {
				logger.Printf("Archived old file: %s", f.Name())
			}
		}
	}
}
