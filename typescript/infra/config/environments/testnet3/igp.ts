import {
  ChainMap,
  GasOracleContractType,
  OverheadIgpConfig,
  defaultMultisigIsmConfigs,
  multisigIsmVerificationCost,
} from '@hyperlane-xyz/sdk';
import { exclude, objMap } from '@hyperlane-xyz/utils';

import { TestnetChains, chainNames } from './chains';
import { owners } from './owners';

function getGasOracles(local: TestnetChains) {
  return Object.fromEntries(
    exclude(local, chainNames).map((name) => [
      name,
      GasOracleContractType.StorageGasOracle,
    ]),
  );
}

export const igp: ChainMap<OverheadIgpConfig> = objMap(
  owners,
  (chain, owner) => {
    return {
      owner,
      oracleKey: owner,
      beneficiary: owner,
      gasOracleType: getGasOracles(chain),
      overhead: Object.fromEntries(
        exclude(chain, chainNames).map((remote) => [
          remote,
          multisigIsmVerificationCost(
            defaultMultisigIsmConfigs[remote].threshold,
            defaultMultisigIsmConfigs[remote].validators.length,
          ),
        ]),
      ),
    };
  },
);
