package cmd

import (
	"github.com/spf13/cobra"
)

var componentCmd = &cobra.Command{
	Use:   "component",
	Short: "Interact with components of a Lokomotive cluster",
}

func init() {
	rootCmd.AddCommand(componentCmd)
	addKubeConfigFlag(componentCmd)
}
