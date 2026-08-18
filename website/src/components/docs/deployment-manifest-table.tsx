import { readFileSync } from "node:fs";
import path from "node:path";

const deploymentManifests = {
  "X Layer Testnet": "xlayer-testnet.json",
} as const;

type DeploymentManifest = {
  grantline: { proxy: string; protocolAdmin: string };
  admin: { address: string };
  modules: {
    registry: { proxy: string };
    evaluator: { proxy: string };
    escalationManager: { proxy: string };
    executor: { proxy: string };
    vaultFactory: { proxy: string };
  };
  vaultImplementation: { address: string };
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
    ["Grantline", manifest.grantline.proxy],
    ["GrantlineAdmin", manifest.admin.address],
    ["MandateRegistry", manifest.modules.registry.proxy],
    ["MandateEvaluator", manifest.modules.evaluator.proxy],
    ["EscalationManager", manifest.modules.escalationManager.proxy],
    ["VaultExecutor", manifest.modules.executor.proxy],
    ["VaultFactory", manifest.modules.vaultFactory.proxy],
    ["Vault Implementation", manifest.vaultImplementation.address],
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
