import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

import { utils } from '@hyperlane-xyz/utils';

import {
  BadRecipient1__factory,
  BadRecipient2__factory,
  BadRecipient3__factory,
  BadRecipient5__factory,
  BadRecipient6__factory,
  TestMailboxV2,
  TestMailboxV2__factory,
  TestModule,
  TestModule__factory,
  TestRecipient__factory,
} from '../types';

import { inferMessageValues } from './lib/mailboxes';

const localDomain = 1000;
const destDomain = 2000;
// const ONLY_OWNER_REVERT_MSG = 'Ownable: caller is not the owner';

describe('Mailbox', async () => {
  let mailbox: TestMailboxV2, module: TestModule, signer: SignerWithAddress;

  before(async () => {});

  beforeEach(async () => {
    [signer] = await ethers.getSigners();
    const moduleFactory = new TestModule__factory(signer);
    module = await moduleFactory.deploy();
    const mailboxFactory = new TestMailboxV2__factory(signer);
    mailbox = await mailboxFactory.deploy(localDomain);
    await mailbox.initialize(module.address);
  });

  it('Cannot be initialized twice', async () => {
    await expect(mailbox.initialize(module.address)).to.be.revertedWith(
      'Initializable: contract is already initialized',
    );
  });

  describe('#dispatch', () => {
    let recipient: SignerWithAddress, message: string, id: string, body: string;
    before(async () => {
      [, recipient] = await ethers.getSigners();
      ({ message, id, body } = await inferMessageValues(
        mailbox,
        signer.address,
        destDomain,
        recipient.address,
        'message',
      ));
    });

    it('Does not dispatch too large messages', async () => {
      const longMessage = `0x${Buffer.alloc(3000).toString('hex')}`;
      await expect(
        mailbox.dispatch(
          destDomain,
          utils.addressToBytes32(recipient.address),
          longMessage,
        ),
      ).to.be.revertedWith('msg too long');
    });

    it('Dispatches a message', async () => {
      // Send message with signer address as msg.sender
      await expect(
        mailbox
          .connect(signer)
          .dispatch(
            destDomain,
            utils.addressToBytes32(recipient.address),
            body,
          ),
      )
        .to.emit(mailbox, 'Dispatch')
        .withArgs(id, message);
    });

    it('Returns the id of the dispatched message', async () => {
      const actualId = await mailbox
        .connect(signer)
        .callStatic.dispatch(
          destDomain,
          utils.addressToBytes32(recipient.address),
          body,
        );

      expect(actualId).equals(id);
    });
  });

  describe('#process', () => {
    const badRecipientFactories = [
      BadRecipient1__factory,
      BadRecipient2__factory,
      BadRecipient3__factory,
      BadRecipient5__factory,
      BadRecipient6__factory,
    ];
    let message: string, id: string, recipient: string;

    beforeEach(async () => {
      await module.setAccept(true);
      const recipientF = new TestRecipient__factory(signer);
      recipient = utils.addressToBytes32((await recipientF.deploy()).address);
      ({ message, id } = await inferMessageValues(
        mailbox,
        signer.address,
        localDomain,
        recipient,
        'message',
      ));
    });

    it('processes a message', async () => {
      await expect(mailbox.process('0x', message)).to.emit(mailbox, 'Process');
      expect(await mailbox.delivered(id)).to.be.true;
    });

    it('Rejects an already-processed message', async () => {
      await mailbox.setMessageDelivered(id, true);

      // Try to process message again
      await expect(mailbox.process('0x', message)).to.be.revertedWith(
        'delivered',
      );
    });

    it('Fails to process message when rejected by module', async () => {
      await module.setAccept(false);
      await expect(mailbox.process('0x', message)).to.be.revertedWith(
        '!module',
      );
    });

    for (let i = 0; i < badRecipientFactories.length; i++) {
      it(`Fails to process a message for a badly implemented recipient (${
        i + 1
      })`, async () => {
        const factory = new badRecipientFactories[i](signer);
        const badRecipient = await factory.deploy();

        ({ message } = await inferMessageValues(
          mailbox,
          signer.address,
          localDomain,
          badRecipient.address,
          'message',
        ));
        await expect(mailbox.process('0x', message)).to.be.reverted;
      });
    }

    // TODO: Fails to process with wrong version..
    it('Fails to process message with wrong destination Domain', async () => {
      ({ message } = await inferMessageValues(
        mailbox,
        signer.address,
        localDomain + 1,
        recipient,
        'message',
      ));

      await expect(mailbox.process('0x', message)).to.be.revertedWith(
        '!destination',
      );
    });

    it('Fails to process message sent to a non-existent contract address', async () => {
      ({ message } = await inferMessageValues(
        mailbox,
        signer.address,
        localDomain,
        '0x1234567890123456789012345678901234567890', // non-existent contract address
        'message',
      ));
      await expect(mailbox.process('0x', message)).to.be.reverted;
    });
  });

  /*
  describe('#setValidatorManager', async () => {
    it('Allows owner to update the ValidatorManager', async () => {
      const mailboxFactory = new TestMailboxV2__factory(owner);
      const newValidatorManager = await mailboxFactory.deploy(localDomain);
      await expect(
        mailbox.setValidatorManager(newValidatorManager.address),
      ).to.emit(mailbox, 'ValidatorManagerSet');
      expect(await mailbox.validatorManager()).to.equal(
        newValidatorManager.address,
      );
    });
    it('Does not allow nonowner to update the ValidatorManager', async () => {
      await expect(
        mailbox.connect(nonowner).setValidatorManager(mailbox.address),
      ).to.be.revertedWith(ONLY_OWNER_REVERT_MSG);
    });
  });
  */
});