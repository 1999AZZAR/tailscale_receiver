package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

const version = "3.1.0"

var logger = log.New(os.Stdout, "", log.LstdFlags)

type Config struct {
	TargetDir    string
	TargetUser   string
	PollInterval time.Duration
	LogLevel     string
	ArchiveDays  int
	Once         bool
}

func main() {
	cfg, ok := parseFlags()
	if !ok {
		return
	}

	logger.SetPrefix("[tailscale-receiver] ")
	logger.Printf("v%s starting — target=%s user=%s interval=%s", version, cfg.TargetDir, cfg.TargetUser, cfg.PollInterval)

	if cfg.LogLevel == "debug" {
		logger.SetFlags(log.LstdFlags | log.Lshortfile)
	}

	if err := preflightChecks(cfg); err != nil {
		logger.Fatalf("preflight: %v", err)
	}

	if err := os.MkdirAll(cfg.TargetDir, 0755); err != nil {
		logger.Fatalf("mkdir %s: %v", cfg.TargetDir, err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if cfg.Once {
		processFiles(cfg)
		manageArchive(cfg)
		return
	}

	ticker := time.NewTicker(cfg.PollInterval)
	defer ticker.Stop()

	archiveTicker := time.NewTicker(time.Hour)
	defer archiveTicker.Stop()

	// initial cycle
	if isTailscaleUp() {
		processFiles(cfg)
		manageArchive(cfg)
	} else {
		logger.Println("tailscale not running at startup, will retry")
	}

	for {
		select {
		case <-ctx.Done():
			logger.Println("shutdown")
			return
		case <-ticker.C:
			if !isTailscaleUp() {
				continue
			}
			processFiles(cfg)
		case <-archiveTicker.C:
			if isTailscaleUp() {
				manageArchive(cfg)
			}
		}
	}
}

func parseFlags() (Config, bool) {
	var (
		targetDir   = flag.String("dir", "", "download directory (default: ~/Downloads/tailscale of TARGET_USER)")
		targetUser  = flag.String("user", os.Getenv("USER"), "owner of received files")
		pollSec     = flag.Int("interval", 15, "poll interval in seconds")
		logLevel    = flag.String("log", "info", "log level (info|debug)")
		archiveDays = flag.Int("archive-days", 14, "archive files older than N days")
		once        = flag.Bool("once", false, "run once and exit")
		showVersion = flag.Bool("version", false, "show version and exit")
	)
	flag.Parse()

	if *showVersion {
		fmt.Printf("tailscale-receiver v%s %s/%s\n", version, runtime.GOOS, runtime.GOARCH)
		os.Exit(0)
	}

	cfg := Config{
		TargetDir:    *targetDir,
		TargetUser:   *targetUser,
		PollInterval: time.Duration(*pollSec) * time.Second,
		LogLevel:     *logLevel,
		ArchiveDays:  *archiveDays,
		Once:         *once,
	}

	// env overrides
	envDir := os.Getenv("TARGET_DIR")
	envUser := os.Getenv("TARGET_USER")

	if envUser != "" {
		cfg.TargetUser = envUser
	}

	// default target dir: use TARGET_USER's home, not the running process's home
	if envDir != "" {
		cfg.TargetDir = envDir
	} else if cfg.TargetDir == "" {
		cfg.TargetDir = defaultTargetDir(cfg.TargetUser)
	}

	if v := os.Getenv("LOG_LEVEL"); v != "" {
		cfg.LogLevel = v
	}
	if v := os.Getenv("POLL_INTERVAL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			cfg.PollInterval = d
		}
	}
	if v := os.Getenv("ARCHIVE_DAYS"); v != "" {
		if n, err := fmt.Sscanf(v, "%d", &cfg.ArchiveDays); err == nil && n == 1 {
			// ok
		}
	}

	if cfg.PollInterval < time.Second {
		cfg.PollInterval = time.Second
	}
	if cfg.ArchiveDays < 0 {
		cfg.ArchiveDays = 0
	}
	if cfg.LogLevel != "debug" {
		cfg.LogLevel = "info"
	}

	return cfg, true
}

func defaultTargetDir(user string) string {
	home, err := userHomeDir(user)
	if err != nil {
		return "/tmp/tailscale-receiver"
	}
	return filepath.Join(home, "Downloads", "tailscale")
}

func userHomeDir(user string) (string, error) {
	out, err := exec.Command("getent", "passwd", user).Output()
	if err != nil {
		return "", err
	}
	parts := strings.Split(strings.TrimSpace(string(out)), ":")
	if len(parts) < 6 {
		return "", fmt.Errorf("unexpected passwd format for %s", user)
	}
	return parts[5], nil
}

func preflightChecks(cfg Config) error {
	var errs []string

	// tailscale binary
	if _, err := exec.LookPath("tailscale"); err != nil {
		errs = append(errs, "tailscale binary not found in PATH")
	}

	// target user exists
	if _, err := userLookup(cfg.TargetUser); err != nil {
		errs = append(errs, fmt.Sprintf("user %q not found: %v", cfg.TargetUser, err))
	}

	if _, err := exec.LookPath("notify-send"); err == nil {
		logger.Println("notify-send found, desktop notifications enabled")
	} else {
		logger.Println("notify-send not found, desktop notifications disabled")
	}

	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "; "))
	}
	return nil
}

type UserInfo struct {
	UID      int
	GID      int
	Username string
}

func userLookup(username string) (*UserInfo, error) {
	cmd := exec.Command("id", "-u", username)
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("id -u %s: %w", username, err)
	}
	var uid int
	if _, err := fmt.Sscanf(string(out), "%d", &uid); err != nil {
		return nil, fmt.Errorf("parse uid: %w", err)
	}

	cmd = exec.Command("id", "-g", username)
	out, err = cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("id -g %s: %w", username, err)
	}
	var gid int
	if _, err := fmt.Sscanf(string(out), "%d", &gid); err != nil {
		return nil, fmt.Errorf("parse gid: %w", err)
	}

	return &UserInfo{UID: uid, GID: gid, Username: username}, nil
}

func isTailscaleUp() bool {
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
	cmd := exec.Command("tailscale", "file", "get", "--conflict=rename", cfg.TargetDir)
	out, err := cmd.CombinedOutput()
	if err != nil {
		if len(out) > 0 {
			logger.Printf("file get: %s", strings.TrimSpace(string(out)))
		}
		if isNoFilesError(err, out) {
			return
		}
		logger.Printf("file get error (will retry): %v", err)
		return
	}

	files, err := os.ReadDir(cfg.TargetDir)
	if err != nil {
		logger.Printf("read dir %s: %v", cfg.TargetDir, err)
		return
	}

	fixed := 0
	for _, f := range files {
		if f.IsDir() {
			continue
		}
		fPath := filepath.Join(cfg.TargetDir, f.Name())

		if !isRootOwned(f) {
			continue
		}

		logger.Printf("received: %s", f.Name())
		if err := fixOwnership(fPath, cfg); err != nil {
			logger.Printf("chown %s: %v", f.Name(), err)
			continue
		}
		notifyUser(f.Name(), cfg)
		fixed++
	}

	if fixed > 0 && cfg.LogLevel == "debug" {
		logger.Printf("fixed ownership for %d file(s)", fixed)
	}
}

func isNoFilesError(err error, out []byte) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	if strings.Contains(msg, "no files") || strings.Contains(msg, "no such file") {
		return true
	}
	return strings.Contains(strings.ToLower(string(out)), "no files to receive")
}

func isRootOwned(f fs.DirEntry) bool {
	info, err := f.Info()
	if err != nil {
		return false
	}
	stat, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return false
	}
	return stat.Uid == 0
}

func fixOwnership(path string, cfg Config) error {
	uinfo, err := userLookup(cfg.TargetUser)
	if err != nil {
		return err
	}
	return os.Chown(path, uinfo.UID, uinfo.GID)
}

func notifyUser(filename string, cfg Config) {
	uinfo, err := userLookup(cfg.TargetUser)
	if err != nil {
		return
	}
	if _, err := exec.LookPath("notify-send"); err != nil {
		return
	}

	display := os.Getenv("DISPLAY")
	wayland := os.Getenv("WAYLAND_DISPLAY")
	dbusAddr := os.Getenv("DBUS_SESSION_BUS_ADDRESS")

	if display == "" && wayland == "" {
		display = detectDisplay(cfg.TargetUser)
		if display == "" {
			return
		}
	}
	if dbusAddr == "" {
		userBus := filepath.Join("/run/user", fmt.Sprint(uinfo.UID), "bus")
		if _, err := os.Stat(userBus); err == nil {
			dbusAddr = "unix:path=" + userBus
		}
	}

	cmd := exec.Command("notify-send", "Tailscale Receiver", "Received: "+filename, "-i", "document-save")
	cmd.SysProcAttr = &syscall.SysProcAttr{}
	cmd.SysProcAttr.Credential = &syscall.Credential{
		Uid: uint32(uinfo.UID),
		Gid: uint32(uinfo.GID),
	}

	if display != "" {
		cmd.Env = append(cmd.Env, "DISPLAY="+display)
	}
	if wayland != "" {
		cmd.Env = append(cmd.Env, "WAYLAND_DISPLAY="+wayland)
	}
	if dbusAddr != "" {
		cmd.Env = append(cmd.Env, "DBUS_SESSION_BUS_ADDRESS="+dbusAddr)
	}

	cmd.Run()
}

func detectDisplay(user string) string {
	cmd := exec.Command("loginctl", "show-user", user, "--property=Display", "--value")
	out, err := cmd.Output()
	if err == nil {
		if d := strings.TrimSpace(string(out)); d != "" {
			return ":" + d
		}
	}
	for _, d := range []string{":0", ":1"} {
		sock := filepath.Join("/tmp/.X11-unix", "X"+strings.TrimPrefix(d, ":"))
		if _, err := os.Stat(sock); err == nil {
			return d
		}
	}
	return ""
}

func manageArchive(cfg Config) {
	if cfg.ArchiveDays <= 0 {
		return
	}
	archivePath := filepath.Join(cfg.TargetDir, "archive")
	if err := os.MkdirAll(archivePath, 0755); err != nil {
		logger.Printf("mkdir archive: %v", err)
		return
	}

	files, err := os.ReadDir(cfg.TargetDir)
	if err != nil {
		logger.Printf("read dir for archive: %v", err)
		return
	}

	cutoff := time.Now().Add(-time.Duration(cfg.ArchiveDays) * 24 * time.Hour)
	moved := 0
	for _, f := range files {
		if f.IsDir() {
			continue
		}
		info, err := f.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(cutoff) {
			old := filepath.Join(cfg.TargetDir, f.Name())
			dst := filepath.Join(archivePath, f.Name())
			if err := os.Rename(old, dst); err != nil {
				logger.Printf("archive %s: %v", f.Name(), err)
			} else {
				moved++
			}
		}
	}
	if moved > 0 && cfg.LogLevel == "debug" {
		logger.Printf("archived %d file(s)", moved)
	}
}
