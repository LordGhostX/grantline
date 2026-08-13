import { readFileSync } from "node:fs";
import path from "node:path";

const deploymentManifests = {
  "X Layer Testnet": "xlayer-testnet.json",
} as const;

type DeploymentManifest = {
  vault: { address: string };
  mandateRegistry: { address: string };
  mandateEvaluator: { address: string };
  escalationManager: { address: string };
  vaultExecutor: { address: string };
};

const deploymentsDirectory = path.join(process.cwd(), "data", "deployments");

function loadDeployments() {
  return Object.entries(deploymentManifests).map(([name, fileName]) => {
    const filePath = path.join(deploymentsDirectory, fileName);
    const manifest = JSON.parse(
      readFileSync(filePath, "utf8"),
    ) as DeploymentManifest;

    return {
      name,
      manifest,
    };
  });
}

function getComponents(manifest: DeploymentManifest) {
  return [
    ["Vault", manifest.vault.address],
    ["MandateRegistry", manifest.mandateRegistry.address],
    ["MandateEvaluator", manifest.mandateEvaluator.address],
    ["EscalationManager", manifest.escalationManager.address],
    ["VaultExecutor", manifest.vaultExecutor.address],
  ] as const;
}

export function getDeploymentManifestMarkdown() {
  return loadDeployments()
    .map(({ name, manifest }) => {
      const rows = getComponents(manifest)
        .map(([component, address]) => `| ${component} | \`${address}\` |`)
        .join("\n");

      return [
        `### ${name}`,
        "",
        "| Component | Address |",
        "| --- | --- |",
        rows,
      ].join("\n");
    })
    .join("\n\n");
}

export function DeploymentManifestTables() {
  const deployments = loadDeployments();

  return (
    <>
      {deployments.map(({ name, manifest }) => {
        const components = getComponents(manifest);

        return (
          <section key={name}>
            <h3>{name}</h3>
            <table>
              <thead>
                <tr>
                  <th>Component</th>
                  <th>Address</th>
                </tr>
              </thead>
              <tbody>
                {components.map(([component, address]) => (
                  <tr key={component}>
                    <td>{component}</td>
                    <td>
                      <code>{address}</code>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
        );
      })}
    </>
  );
}
