// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../governors/SecurityCouncilMemberElectionGovernor.sol";
import "../governors/SecurityCouncilNomineeElectionGovernor.sol";
import "../SecurityCouncilManager.sol";
import "../SecurityCouncilMemberRemovalGovernor.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../interfaces/ISecurityCouncilManager.sol";
import "../../ArbitrumTimelock.sol";
import "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

struct DeployParams {
    address _govChainEmergencySecurityCouncil;
    address _l1CoreGovTimelock;
    address _l2CoreGovTimelock;
    address _proxyAdmin;
    address[] _secondCohort;
    address[] _firstCohort;
    address l2UpgradeExecutor;
    address arbToken;
    uint256 _minL1TimelockDelay;
    uint256 _removalGovVotingDelay;
    uint256 _removalGovVotingPeriod;
    uint256 _removalGovQuorumNumerator;
    uint256 _removalGovProposalThreshold;
    uint256 _removalGovVoteSuccessNumerator;
    uint64 _removalGovMinPeriodAfterQuorum;
    SecurityCouncilData[] _securityCouncils;
    uint256 _fullWeightDuration;
    // governor params
    Cohort firstCohort;
    SecurityCouncilNomineeElectionGovernor.Date firstNominationStartDate;
    uint256 nominationFrequency;
    uint256 nomineeVettingDuration;
    address nomineeVetter;
    uint256 nomineeQuorumNumerator;
    uint256 nomineeVotingPeriod;
    uint256 memberVotingPeriod;
    uint256 memberFullWeightDurationNumerator;
    uint256 memberDecreasingWeightDurationNumerator;
    uint256 memberDurationDenominator;
}

/// @notice Factory for deploying L2 Security Council management contracts

contract L2SecurityCouncilMgmtFactory is Ownable {
    event ContractsDeployed(DeployedContracts deployedContracts);

    struct DeployedContracts {
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor;
        SecurityCouncilMemberElectionGovernor memberElectionGovernor;
        ISecurityCouncilManager securityCouncilManager;
        address l2EmergencySecurityCouncilUpgradeExecutor;
        address l2NonEmergencySecurityCouncilUpgradeExecutor;
        SecurityCouncilMemberRemovalGovernor securityCouncilMemberRemoverGov;
        ArbitrumTimelock memberRemovalGovTimelock;
    }

    function deploy(DeployParams memory dp) external onlyOwner returns (DeployedContracts memory) {
        require(
            Address.isContract(dp._govChainEmergencySecurityCouncil),
            "L2SecurityCouncilMgmtFactory: _govChainEmergencySecurityCouncil is not a contract"
        );
        require(
            Address.isContract(dp._proxyAdmin),
            "L2SecurityCouncilMgmtFactory: _proxyAdmin is not a contract"
        );
        require(
            Address.isContract(dp.l2UpgradeExecutor),
            "L2SecurityCouncilMgmtFactory: l2UpgradeExecutor is not a contract"
        );
        require(
            Address.isContract(dp.arbToken),
            "L2SecurityCouncilMgmtFactory: arbToken is not a contract"
        );

        DeployedContracts memory deployedContracts;

        // deploy nominee election governor
        deployedContracts.nomineeElectionGovernor = SecurityCouncilNomineeElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilNomineeElectionGovernor()),
                    dp._proxyAdmin,
                    bytes("")
                )
            )
        );

        // deploy member election governor
        deployedContracts.memberElectionGovernor = SecurityCouncilMemberElectionGovernor(
            payable(
                new TransparentUpgradeableProxy(
                    address(new SecurityCouncilMemberElectionGovernor()),
                    dp._proxyAdmin,
                    bytes("")
                )
            )
        );

        // deploy security council manager
        deployedContracts.securityCouncilManager = ISecurityCouncilManager(
            address(
                new TransparentUpgradeableProxy(
                address(new SecurityCouncilManager()),
                dp._proxyAdmin,
                bytes(""))
            )
        );

        // deploy security council member remover gov
        deployedContracts.securityCouncilMemberRemoverGov = SecurityCouncilMemberRemovalGovernor(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                    address(new SecurityCouncilMemberRemovalGovernor()),
                    dp._proxyAdmin,
                    bytes("")
                    )
                )
            )
        );

        // deploy member removal gov timelock
        deployedContracts.memberRemovalGovTimelock = ArbitrumTimelock(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                    address(new ArbitrumTimelock()),
                    dp._proxyAdmin,
                    bytes("")
                    )
                )
            )
        );
        // create council manager roles
        address[] memory memberRemovers = new address[](2);
        memberRemovers[0] = address(deployedContracts.memberRemovalGovTimelock);
        memberRemovers[1] = dp._govChainEmergencySecurityCouncil;
        SecurityCouncilManagerRoles memory roles = SecurityCouncilManagerRoles({
            admin: dp.l2UpgradeExecutor,
            cohortUpdator: address(deployedContracts.memberElectionGovernor),
            memberAdder: dp._govChainEmergencySecurityCouncil,
            memberRemovers: memberRemovers,
            memberRotator: dp._govChainEmergencySecurityCouncil
        });

        // initialize securityCouncilManager
        deployedContracts.securityCouncilManager.initialize(
            dp._secondCohort,
            dp._firstCohort,
            dp._securityCouncils,
            roles,
            dp._l1CoreGovTimelock,
            payable(dp._l2CoreGovTimelock),
            dp._minL1TimelockDelay
        );

        deployedContracts.memberRemovalGovTimelock.initialize(0, new address[](0), new address[](0));
        
        // removal gov can propose to timelock
        deployedContracts.memberRemovalGovTimelock.grantRole(
            deployedContracts.memberRemovalGovTimelock.PROPOSER_ROLE(),
            address(deployedContracts.securityCouncilMemberRemoverGov)
        );
        // anyone can execute
        deployedContracts.memberRemovalGovTimelock.grantRole(
            deployedContracts.memberRemovalGovTimelock.EXECUTOR_ROLE(), address(0)
        );

        // DAO (upgrade executor) is admin
        deployedContracts.memberRemovalGovTimelock.grantRole(
            deployedContracts.memberRemovalGovTimelock.TIMELOCK_ADMIN_ROLE(), dp.l2UpgradeExecutor
        );
        // TODO do we need to revoke the TIMELOCK_ADMIN_ROLE from the timelock itself?

        _initRemovalGov(
            dp,
            deployedContracts.memberRemovalGovTimelock,
            deployedContracts.securityCouncilMemberRemoverGov
        );

        _initElectionGovernors(
            dp,
            deployedContracts.securityCouncilManager,
            deployedContracts.nomineeElectionGovernor,
            deployedContracts.memberElectionGovernor
        );

        emit ContractsDeployed(deployedContracts);
        return deployedContracts;
    }

    function _initRemovalGov(
        DeployParams memory dp,
        ArbitrumTimelock _memberRemovalGovTimelock,
        SecurityCouncilMemberRemovalGovernor securityCouncilMemberRemoverGov
    ) internal {
        securityCouncilMemberRemoverGov.initialize({
            _voteSuccessNumerator: dp._removalGovVoteSuccessNumerator,
            _token: IVotesUpgradeable(dp.arbToken),
            _timelock: _memberRemovalGovTimelock,
            _owner: dp.l2UpgradeExecutor,
            _votingDelay: dp._removalGovVotingDelay,
            _votingPeriod: dp._removalGovVotingPeriod,
            _quorumNumerator: dp._removalGovQuorumNumerator,
            _proposalThreshold: dp._removalGovProposalThreshold,
            _minPeriodAfterQuorum: dp._removalGovMinPeriodAfterQuorum
        });
    }

    function _initElectionGovernors(
        DeployParams memory dp,
        ISecurityCouncilManager securityCouncilManager,
        SecurityCouncilNomineeElectionGovernor nomineeElectionGovernor,
        SecurityCouncilMemberElectionGovernor memberElectionGovernor
    ) internal {
        nomineeElectionGovernor.initialize(
            SecurityCouncilNomineeElectionGovernor.InitParams({
                targetNomineeCount: dp._secondCohort.length,
                firstNominationStartDate: dp.firstNominationStartDate,
                nomineeVettingDuration: dp.nomineeVettingDuration,
                nomineeVetter: dp.nomineeVetter,
                securityCouncilManager: securityCouncilManager,
                securityCouncilMemberElectionGovernor: memberElectionGovernor,
                token: IVotesUpgradeable(dp.arbToken),
                owner: dp.l2UpgradeExecutor,
                quorumNumeratorValue: dp.nomineeQuorumNumerator,
                votingPeriod: dp.nomineeVotingPeriod
            })
        );

        memberElectionGovernor.initialize({
            _nomineeElectionGovernor: nomineeElectionGovernor,
            _securityCouncilManager: securityCouncilManager,
            _token: IVotesUpgradeable(dp.arbToken),
            _owner: dp.l2UpgradeExecutor,
            _votingPeriod: dp.memberVotingPeriod,
            _targetMemberCount: dp._firstCohort.length,
            _fullWeightDuration: dp._fullWeightDuration
        });
    }
}
