/*
Copyright 2025.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"flag"
	"net/http"
	"os"
	"time"

	// Import k8s.io packages
	"k8s.io/apimachinery/pkg/runtime"
	utilruntime "k8s.io/apimachinery/pkg/util/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	_ "k8s.io/client-go/plugin/pkg/client/auth"

	// Import controller-runtime packages
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/healthz"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
	"sigs.k8s.io/controller-runtime/pkg/webhook"

	// Import KubeVirt API
	kubevirtv1 "kubevirt.io/api/core/v1"

	// Import your controller
	"setofangdar.polito.it/vm-watcher/internal/controller"
	//+kubebuilder:scaffold:imports
)

var (
	scheme   = runtime.NewScheme()
	setupLog = ctrl.Log.WithName("setup")
)

func init() {
	utilruntime.Must(clientgoscheme.AddToScheme(scheme))

	// Add KubeVirt scheme
	utilruntime.Must(kubevirtv1.AddToScheme(scheme))

	//+kubebuilder:scaffold:scheme
}

func main() {
	var metricsAddr string
	var enableLeaderElection bool
	var probeAddr string
	var guacamoleBaseURL string
	var guacamoleUsername string
	var guacamolePassword string
	var httpTimeout time.Duration

	flag.StringVar(&metricsAddr, "metrics-bind-address", ":8080", "The address the metric endpoint binds to.")
	flag.StringVar(&probeAddr, "health-probe-bind-address", ":8081", "The address the probe endpoint binds to.")
	flag.BoolVar(&enableLeaderElection, "leader-elect", false,
		"Enable leader election for controller manager. "+
			"Enabling this will ensure there is only one active controller manager.")
	flag.StringVar(&guacamoleBaseURL, "guacamole-url", "", "Base URL of Apache Guacamole (e.g., https://guacamole.example.com)")
	flag.StringVar(&guacamoleUsername, "guacamole-username", "", "Guacamole admin username")
	flag.StringVar(&guacamolePassword, "guacamole-password", "", "Guacamole admin password")
	flag.DurationVar(&httpTimeout, "http-timeout", 30*time.Second, "HTTP client timeout for Guacamole API calls")

	opts := zap.Options{
		Development: true,
	}
	opts.BindFlags(flag.CommandLine)
	flag.Parse()

	ctrl.SetLogger(zap.New(zap.UseFlagOptions(&opts)))

	// Get Guacamole configuration from environment variables if not provided via flags
	if guacamoleBaseURL == "" {
		guacamoleBaseURL = os.Getenv("GUACAMOLE_BASE_URL")
	}
	if guacamoleUsername == "" {
		guacamoleUsername = os.Getenv("GUACAMOLE_USERNAME")
	}
	if guacamolePassword == "" {
		guacamolePassword = os.Getenv("GUACAMOLE_PASSWORD")
	}

	// Validate required configuration
	if guacamoleBaseURL == "" {
		setupLog.Error(nil, "Guacamole base URL is required. Set via --guacamole-url flag or GUACAMOLE_BASE_URL environment variable")
		os.Exit(1)
	}
	if guacamoleUsername == "" {
		setupLog.Error(nil, "Guacamole username is required. Set via --guacamole-username flag or GUACAMOLE_USERNAME environment variable")
		os.Exit(1)
	}
	if guacamolePassword == "" {
		setupLog.Error(nil, "Guacamole password is required. Set via --guacamole-password flag or GUACAMOLE_PASSWORD environment variable")
		os.Exit(1)
	}

	mgr, err := ctrl.NewManager(ctrl.GetConfigOrDie(), ctrl.Options{
		Scheme: scheme,
		Metrics: metricsserver.Options{
			BindAddress: metricsAddr,
		},
		WebhookServer: webhook.NewServer(webhook.Options{
			Port: 9443,
		}),
		HealthProbeBindAddress: probeAddr,
		LeaderElection:         enableLeaderElection,
		LeaderElectionID:       "vm-watcher.setofangdar.polito.it",
	})
	if err != nil {
		setupLog.Error(err, "unable to start manager")
		os.Exit(1)
	}

	// Setup HTTP client with timeout
	httpClient := &http.Client{
		Timeout: httpTimeout,
		Transport: &http.Transport{
			MaxIdleConns:       10,
			IdleConnTimeout:    30 * time.Second,
			DisableCompression: true,
		},
	}

	if err = (&controller.VirtualMachineReconciler{
		Client:            mgr.GetClient(),
		Scheme:            mgr.GetScheme(),
		GuacamoleBaseURL:  guacamoleBaseURL,
		GuacamoleUsername: guacamoleUsername,
		GuacamolePassword: guacamolePassword,
		HTTPClient:        httpClient,
	}).SetupWithManager(mgr); err != nil {
		setupLog.Error(err, "unable to create controller", "controller", "VirtualMachine")
		os.Exit(1)
	}
	//+kubebuilder:scaffold:builder

	if err := mgr.AddHealthzCheck("healthz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up health check")
		os.Exit(1)
	}
	if err := mgr.AddReadyzCheck("readyz", healthz.Ping); err != nil {
		setupLog.Error(err, "unable to set up ready check")
		os.Exit(1)
	}

	setupLog.Info("starting manager",
		"guacamole-url", guacamoleBaseURL,
		"guacamole-username", guacamoleUsername)
	if err := mgr.Start(ctrl.SetupSignalHandler()); err != nil {
		setupLog.Error(err, "problem running manager")
		os.Exit(1)
	}
}
