// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

interface IRewardPool {
    function getPeriodRewards(uint256 index_, uint128 startTime_, uint128 endTime_) external view returns (uint256);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

/// @notice Morpheus BuildersV4 reward-accounting PoC  (Base mainnet, deployed bytecode).
///
/// TARGET      BuildersV4 @ 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9 (Base), pinned fork block
/// INVARIANT   A reward distributor must never pay out more than it accrued:
///                 claimedRewards <= distributedRewards
///             and cumulative payouts must stay inside the reward-pool emission budget allocated to
///             Builders (RewardPool pool 3 emission x networkShare).
///
/// MECHANISM
///   BuildersV4 carries a GLOBAL accumulator `allSubnetsData.rate` and a PER-SUBNET accumulator
///   `subnetsData[s].rate`. A subnet's entitlement is recomputed at claim time as
///       (allSubnetsData.rate - subnetsData[s].rate) * subnetsData[s].deposited / PRECISION
///   `allSubnetsData.rate` rises on every touch of ANY subnet, while `subnetsData[s].rate` only
///   rises when THAT subnet is touched. A subnet nobody touches therefore keeps accruing against a
///   global rate that has already risen from other subnets' activity, so the sum of per-subnet
///   entitlements grows faster than the emission that funds them.
///
/// EVIDENCE
///   test_A  the contract's own two getters disagree by ~69% on the same quantity
///   test_B  executing every subnet's legitimate claim drives claimedRewards ABOVE
///           distributedRewards and makes the contract's own aggregate getter underflow
///   test_C  cumulative claims exceed the pool-3 emission budget allocated to Builders
///   test_D  control - total extracted depends on claim order at the same block
///
/// No owner, multisig or privileged role is used. Each claimer is the `admin` recorded for that
/// subnet, i.e. the ordinary on-chain account entitled to its rewards.
contract BuildersV4OverIssuancePoC is Test {
    address constant BUILDERS = 0x42BB446eAE6dca7723a9eBdb81EA88aFe77eF4B9;
    address constant TREASURY = 0x9eba628581896ce086cb8f1A513ea6097A8FC561;
    address constant MOR = 0x7431aDa8a591C955a994a21710752EF9b882b8e3;
    address constant REWARD_POOL = 0xDC99a8596e395E52aba2BD08C623E1e428Dc3980;

    uint256 constant FORK_BLOCK = 52390000;
    uint256 constant V4_CUT_BLOCK = 39654132;
    uint256 constant POOL_ID = 3;
    uint256 constant PRECISION = 1e25;

    IERC20 mor = IERC20(MOR);
    IRewardPool rp = IRewardPool(REWARD_POOL);

    bytes32[] ids;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC"), FORK_BLOCK);
        // every subnetId that ever emitted
        ids.push(0x01c9c97ce69569af244b25f299f3cc830d98240094d6262b4ad010022d689f73);
        ids.push(0x0365447f7c98fa1070f467f2cc220de7b0b9c17b9664336c10e26ee3182f39d1);
        ids.push(0x03fa50361370455816211100c40123006f5f15b53b290735edc0810fd61e77fd);
        ids.push(0x0aba8305245a8374ff005fe7c6b074ad26a4f880a00ad7d5355728a96e9dbc9c);
        ids.push(0x0b4e662f0a3480ee9117e3c2f0559d3f3295eac04ea52f84c1c5893281f22bb4);
        ids.push(0x0c8d5f4c48826aeecff5b2defb4314351a3ca7f93f7b41d8bb99c47e3aae1360);
        ids.push(0x12114b0a384ce09b8ce5a6a0519b3b6067d8250b82a9f65f26df712af1796d4b);
        ids.push(0x1241e3338597833a68ea15369476b805aa9106da8749b1ebb036027fb63fb9e2);
        ids.push(0x12890c8b23c2a4c1c0957f730b23ed3abba75878002d52bb26fccf39ce7a2cc9);
        ids.push(0x13d14386e0de58be6e88d26c3027b3733c3bbc3c4c6129cb31efb789206382b9);
        ids.push(0x1b2a2d65380953835f7ddf34832cbcc0616739925b84e9276c414792d16143df);
        ids.push(0x1df41cd916959d1163dc8f0671a666ea8a3e434c13e40faef527133b5d167034);
        ids.push(0x1fbe23f711c462994970cdfc79d622754ff43217e235a30a9aea0e62fb9b1020);
        ids.push(0x20ba70f2bbdc384bbc0e016ec2e888c38e6d1a5454555eefdc91d546fccca932);
        ids.push(0x25c16934a56ededa389e347f693f39caa3596a7aff16a3eab9f74bd3b731cf6e);
        ids.push(0x25e349b6e220e73d277d80c4e8279b5bfe33b0adafa90193ab1dc763e5ed5e72);
        ids.push(0x29d6c72e0af35f863f8c8345529ad5ad19b70b0d46225228e27c082710db4bfb);
        ids.push(0x2cef520db0d87be977cc612c0c57e2ef1788fcd8e7032418be1cccea82a603f4);
        ids.push(0x2eaab3c48bb91e1b6012a99adc58e6f21ed3e163e5e76bfab8213e5b58a852c9);
        ids.push(0x3082ff65dbbc9af673b283c31d546436e07875a57eaffa505ce04de42b279306);
        ids.push(0x36aea6a8fbd9382c147c110ff07de962300818995b9961a8fea131d5efc1b1db);
        ids.push(0x36c36fde5da66f0a1106c17a2f59868071f320c0df7a34ce1ed217ee585f89cc);
        ids.push(0x3a770eb03ad423ec6e014c9e165d648f0f38c2408b41c5dd6abb8e2aa9e87e14);
        ids.push(0x3f73d9b00b869a0eebb5325b37c807252a1307bd5390ecde1348aa11233703b2);
        ids.push(0x3fcf0f7bee0e5b848a8637b695cdee03ea0ae9312b4c67cc6261bebe187cb059);
        ids.push(0x40aa9fbd2fde2e6a38510ef730aee171c3e81a4c165bccbddefe4c89b55b2a8d);
        ids.push(0x415471125cc4d03b89818acb8426981fa28a3eee03a9097176297a9a6ae87c8d);
        ids.push(0x4161e9c1fe8d1c79e76218a19770250f3ad39677f567acb895919394ce50b43f);
        ids.push(0x42f02b08eadb43dbc23783822aeba31623e22e2c95e608e48590adb48e7856bf);
        ids.push(0x4501d4e79230adce800ff26e5d2e2ae061f1e54da8508fe17dd1462388fb8373);
        ids.push(0x4885d668c123411736d7fff2f0eba0647fe30de9b523ec8822a1e971820b5792);
        ids.push(0x4898ffbb68a22c4c772a01cb03358795a90faded5a3bfb3fa3d9639d33837b50);
        ids.push(0x4b052d506ed57a8701f1c2eda5b6cba9a16b9bc9674c209c449a6f55430ca330);
        ids.push(0x4c25cd7db02a0d0354010749554d260fec635455aca30f7b4001c222d14d4294);
        ids.push(0x4cbaac02f4c2ff6d72454ec7dc0a7ed0cbd06dff9d70001ab0d0e84508dd2efe);
        ids.push(0x4f20ea35d11e3212db41c368b2b6f66c0fe4c3c6dff2da1b05c475356ba06655);
        ids.push(0x4f42bb9dee66865e920f676995b247c29add563a33a995ea2c90c4e66c10b1f9);
        ids.push(0x51d6bac17c7bf606d2b895ee296a98006bef45af41bb0c2bfca25f748ccaf8df);
        ids.push(0x523c0aeb3052502e24f39efb5a62b8bcec4c1c7f5dda3e6f3901af3d5da281f2);
        ids.push(0x523f1bb39a49927241fcd48dacab09dd72c218bf1e3a01e3206264fd666f0d79);
        ids.push(0x555f4187c49a84c38008e2040d71c71ac7d99c5989ceaaed94993a88edff4ee3);
        ids.push(0x57162dc92bf524418ac35438354b62300ec1b8d80083b2a89859ff2a5c061ba6);
        ids.push(0x5736758632737f7bdcaac5cd3401bf38c12b69033bcc2aa7bc958c8cbe816368);
        ids.push(0x5c92edba5c98bd16497d97c0f5b37dfb696e9330bd12b06804bc45a6d0a619f0);
        ids.push(0x5f11a5393e48117b411c9b14e57aed5cea62541d1c41a161a47ff8233a0c8eb7);
        ids.push(0x5f235b676ea7dcabc2f0c580728f79dd2b6959589b3ea096ac1af055e7666456);
        ids.push(0x6051ba578e8876ce3d68d81a2b741685e4f13ab44fdfb8321d99d39080463424);
        ids.push(0x61eab318875e78d51363bc2ae3a2865f5ea29aae1b0eb0e7617bd80c7cc03574);
        ids.push(0x638451aa95394a1ea79bbf9d15eb532b5beed7f3831ccc8db278654ae30dad27);
        ids.push(0x63891e659ff2ae88fdaf6ff05f07ffbbd4ffbca089600564c7c6c784a96ab0e5);
        ids.push(0x664823f3e70c7f2788e8d393bffbfe1c6cb463d6af29b43933af6cfd7944588f);
        ids.push(0x681f1eeaefbb14a121f5b58ee822c56fb1f213edc49e9188343eaba0b7d279b3);
        ids.push(0x6853bdaac0b14b032091c3495bfe4cf14ba89b86b0859ffdd937f17361befdf1);
        ids.push(0x6881f7f816675f5eaacfd9539c9a36fede0835d3d595c9f61aed4d97c4ec18c5);
        ids.push(0x697230414862bf66950a6394b0fc6a96ef552c301fb5f863c9222d7cc51761f5);
        ids.push(0x6a117ee75d9c3c44c18cf44009429034ad02bd2e14fc3e982e63bdafcd55625c);
        ids.push(0x6c3cf7d13ee27452da3cf752f2c1eb220b3abf4802f4d2c55fef1191983868b1);
        ids.push(0x6c6268250b4191989e3544e9d008ec405ada1f0ce5203e86b2b2fc11c8026d71);
        ids.push(0x6cdddba551e9ea0baad16f5c4c2a723e19525b5809af7762bee624e7454373db);
        ids.push(0x6d4a00233c2192694cf0dc52e0bdfd73e136bd1338fcfced149989e7fa6bbdab);
        ids.push(0x6e01dad5c9ab50624d1dd0cb0fa7fff5110fee914d796a4e341bd3796a5864d2);
        ids.push(0x711021eebd0da96fb62ebce99f332f31245b16f614e25944fc2afd81a5f3aabe);
        ids.push(0x7169601aa382123b982cb9055874ed5ccb7223a5500a2b41aedf013653d3f167);
        ids.push(0x730429d43c917151bf43c3baa677922276bced4eb6718a5cb20a352bcbc0a290);
        ids.push(0x74f4bf2ab130773c22cfbbd2279244d144fdf1cdeafda6392846718c2c6e8141);
        ids.push(0x7671a13aa6295ad5c6f20200935602ffe4cde338d98bdd43979b3664b65ad4ff);
        ids.push(0x773f45fb1df3ae27ba60d371fc36af32fd1896863c842b4c4e89e30668944c0b);
        ids.push(0x78b78019c2d0782c9790a3ae61a899c857d54e4ae6e012caca7338e477857868);
        ids.push(0x78bd2b0149d945aceca59c74c3200f6596494d79862a8ea633d721c89858f016);
        ids.push(0x79275eb5243feee7843a8d417ac479cd6b5635aac92daa8df16b0a4664045162);
        ids.push(0x79611d94d04d7c5a4dcfa6733b4c096a918193b453b10688665088f5183723b1);
        ids.push(0x79ff1428115d80e3d6696e93b0abc0b363f37dd44445c01a964a7d9629420480);
        ids.push(0x7c60385401910d17dba253bd525a1df56854dbca9493b1323532f5dc26a40c9f);
        ids.push(0x7cc3d56efb62fcb844cccd8e71b74c40dc912270bafc60a7d3c438378e431842);
        ids.push(0x7d3cf35ceda5f8ca62b287262ceabebf24450e3747a02f8de5dd0292066c9d32);
        ids.push(0x8036bbb740074d06db6b7741fcf9f52bd25846b9fc7e0a10c983c51530eaa999);
        ids.push(0x8300051e8c548e7fafb03fb90101fe61d495d5ece6d65d0a6da72bc137a1146f);
        ids.push(0x83c5dd436bb2e55e11fa61e24acc79b242e6cdb71cc8b46669d24698b6439643);
        ids.push(0x85e3b554619e2fd48a4ad8c8c2744a9d9686463ac02ff83664c717876c313a88);
        ids.push(0x869196b2e1269739fe75c23354a977955fee4993e686537ead9e44849e02c0cb);
        ids.push(0x8907740984c1d1ebb6db21c7b6f2bc140559794b0a8f517e3f83c4faea03bae3);
        ids.push(0x893060aaa56a2b6b4c30a56940630a94fefa646ed6ca9c5987ca57a0255fc609);
        ids.push(0x8bb6452786155e48063040d7ae34ce4ea10c426eaf87650b59d8db22ec85ce39);
        ids.push(0x8c0816cbb32956f90ca8d0bb346828a991a214129b8bb53f4b14a5053eb22550);
        ids.push(0x8e19376b52a8b1d5108414b9ac51e3e9737699032101515216e0d95b3f895057);
        ids.push(0x8e7ada070e9ad24653a2d85727fcbf1db45a6f48526d918c6148b83f31981010);
        ids.push(0x901a009919d0829383756d730d5ebce305dfbfccee1d587bf54a061ef4ef9139);
        ids.push(0x9063e7cc118239ad52f8ac93133fd4b33f819217f2baad93c899bff7bf569fce);
        ids.push(0x92ec4d95bf8d273481595c40a08ec03642868af7a1ed1a8b64d2372eb6aac33d);
        ids.push(0x940fe2bc6ae55ea082aaefaf7be978090fdc3bc94b390f0b5a741a439b7d501e);
        ids.push(0x96342c265828489a728e6278d3c1eab8f53a89809055b5d6495cb2b39bbf16a2);
        ids.push(0x966710b4bff7486021f6c272f4c9e332cd35eeef58334cc7fc1c02c71088422a);
        ids.push(0x96e624768600a7be0f2a82545d33c137ff3df2f377dc3fdf468308e5b977a72f);
        ids.push(0x975822084ade3f1c75ddb0e4f63500d375330fd2110ee528dec27a44d7040f11);
        ids.push(0x99a0bc16510b4cb8834f87c582caaff9667fe0ce129698cb4bef71354a9de30f);
        ids.push(0x9a7e67694fac9f58c1e1d2b1791c5badfe0eceadb7f377b04bf2f0b00d56b343);
        ids.push(0xa0543eb607e590f79250a1a9d337d41fdf951c5cc732213911bb5a50dd99738b);
        ids.push(0xa1f6876aa288ed12aea544c308056ec643dd965a20b6f2c8129b10fef9b9e949);
        ids.push(0xa47394b19c03fc684630f0a0bf7505e062328dccade7b809ea011198816d8d12);
        ids.push(0xa5de7b70e5572025bd1e82c4081309129c4e47a183d4f76d00c65f9725b2cc14);
        ids.push(0xa7fafe0dddaeea5789018c11d0c420b718734b6c36a454c4613befb9b0e0f69d);
        ids.push(0xaabc7043f8d1616d55ecae080430fb180ece49b4c269377d6f9c830854acabfc);
        ids.push(0xac491f4c14b9f329398b820d2573f73abdf66ebb0c5271fa55c3dcfd5adfa2fd);
        ids.push(0xad925e39a087802d56fc2f774262d2c1bf41344e802328d0aa5fc04dddd526db);
        ids.push(0xb2a83a0ba507aea062072e3c063d6ecf715f6c89edb50cffc70acd82a3102c67);
        ids.push(0xb46506c4174fa5ec7a36fdb4d7a3cd237dd6c60d6b2bcc9e4c1731f9f0e49c6f);
        ids.push(0xb4ded221c6390f8ae22171014b93b9630521c341fd59b2a592962976072e07a2);
        ids.push(0xb518addbd1e3abf0abcd7bd0db4af0eef300983a8573cc66f54426f83e024468);
        ids.push(0xb7a522e752f221b19f80c9f9b5d63206788c70185a3e51c6826c854de1d82ba2);
        ids.push(0xb8e72a8d62004d60faaa59109c64e51c1d9d877a3d2e79abcb0db22fe56041fc);
        ids.push(0xb9086e4900331eb895edf4f6db298bd290d48037c663e6243d0386157dc8d0c7);
        ids.push(0xbffe9cb8e4e2ecba926505a06c6ca3717cb2bdbee65797b1134672765899c0b7);
        ids.push(0xc00e9d8d26a19b9af1ecb5e717182a7db3f5d131ddb324df6e996464c2314ed8);
        ids.push(0xc0302dc46a5b3d7c1ad1ca17aa20d2288f9b21f7917ec891e9c57038abb75a9c);
        ids.push(0xc0aca3a0b3cfab81287943ef4a48e0c2f0441c12beb50fc8c2be3a810bbe0d6c);
        ids.push(0xc0b926f96e1aadbcd04c21c56649e3846b35bcd18ffafc1cdce7a3d8130c419c);
        ids.push(0xc19f7e5c708053019ccf3276584f12b0ff481b69955ea597ed52fdc7b057eea1);
        ids.push(0xc1ecd59a9b43eb728f40009cb3874a209a54233bdc1266193041e5247e0b22ee);
        ids.push(0xc4c0cda80f2ed6be8e46e69cedbd958b3d9e2b81a811d03f16897b939125eabd);
        ids.push(0xc5eb7bc721c7d4daeeed17a01a911eb647914a3288aa0a17f2c8aedf69220189);
        ids.push(0xc6322067e7f69485def3ee562227eb0d87a8d39d26f833d60151d35dbd7ddbad);
        ids.push(0xc846d083253bd6e03b8f451c68dea4ab9ea2c82ed35837ab81e50ded713db502);
        ids.push(0xc8a0087b1d7e5b3a2f18b2d79fd2fbf187802af7370b928ff0e6eacf47341299);
        ids.push(0xc979023bb9bf3b74ae2eca5a210c7297f9e8e604d01a0d6024de07acfa7762fc);
        ids.push(0xcd69610384d862dcae7c4009fa01b20624fe0cbf464d2468a041ffc709bac2de);
        ids.push(0xce715907da6e6e3fd13f7fc5a1b908ba2692926328782a7a7d00c541a4ea39ee);
        ids.push(0xd10962900fa1bf09f05550ab01efa2a1915a3c33a7a2e38a2ced45227c44302d);
        ids.push(0xd36cf10a2fc6460f84bc3d69a34da57d8223d46757eef0326aa23bc8f658e56f);
        ids.push(0xd54b5d5b98308212960e5edb1acd8f248c69201922641a873546662a03528057);
        ids.push(0xd7a4e45eba1ad5fec4557d2de38aa76988611293e4bf45896488d51fa70b82db);
        ids.push(0xd954183b3f97a0e982917900478876501ae2eb85fc1d7fb90f2c34b0c7b65d26);
        ids.push(0xda50f9aa1710272d6c17f84d713b6c8f30b2870c376039e5323852b027a440fa);
        ids.push(0xda589917a3e3836aab6bc61103b436b5a3ab440e9b69715a1618f74f9dda5a7b);
        ids.push(0xdcba960308192a0eb3e6dbd97b27b3cc2454e38d06ef78ced76e7378afb2e5dc);
        ids.push(0xdccb9a7800ec49cd48db4d631f37c63a730ac8e8124901e59dd087ffcfc29564);
        ids.push(0xe100f9d7c463008e46887113fa14bc0ba9caaf90d4465835795f53ebe5056059);
        ids.push(0xe3563eef3a6c3df9b3b82a2bd21f73107d9b635f19442e0189767180a1b9831e);
        ids.push(0xe549e7a894cee208f53e6a5a9df3483cb542861f2fee35947b3ea21adc1ddf8a);
        ids.push(0xe6a0e1d49e89fe89e16ae0586cd20809b94119befafc1b0be11dafcf4c658e7d);
        ids.push(0xe7aa57528844a44f9c1833db28775663b5d16e09c8075407b07c8973bb05d185);
        ids.push(0xe9fba89ca97425c3389c8086a17a75785b04152c035b68b8108980375a60ad21);
        ids.push(0xea0557f07112ab48fd5e07415983165fe08a72f420324aab2e38131b07d8ad3e);
        ids.push(0xed99429be84b05331210ff2d4b1ff17e52876fb7c2a3b72caf3cb0fc8bd97e52);
        ids.push(0xf0133427dac242f09e7826458174b9f99f67e6e3eac74f1d18ffc7d780a1b5ea);
        ids.push(0xf129111951997d1c386be9b7de27d4c74490c42ad0ffbcb65e380d17f8a8ea3d);
        ids.push(0xf18718acbee73105d304ee13f506a5765de4885f1c62a8f5a97089702c40507a);
        ids.push(0xf4a1ea01b4f52b7328a1665df387c9ffeced4c7a3233e7316302d0ba45a0eaba);
        ids.push(0xf510a7f4efbcb090687018eebc97c61d447a833fbd1ba4333b0fc2e4541b5def);
        ids.push(0xf610f88085f5955bccb50431e1315a28335522d87be5000ff334274cc9985741);
        ids.push(0xf8c784db930f5b824609b2a64bc7135b089666624ba6e3a8cca427eafcf572cd);
        ids.push(0xfc9d100f7a082467b344c807c5952038c31abe80caefbdeeb884ce252e15351a);
        ids.push(0xfd1572a2a5e1bc5b350e34b0789326b6a02c14b357c67405d537eb4159df029d);
        ids.push(0xfde7d8a5de1071db3911b562a5647dedd538ff73d01aaa7862658dec569d0707);
        ids.push(0xfed9bfd50aee8bff13e937220ebb0ecaad23bff45909b679d0edcfa4c0e87da0);
        ids.push(0xff2a83dce744d5c9b6dfe11813d09104cf0d01b7ef1b3ab4bc228b50c0f692d4);
        ids.push(0xffb8adb550865fd1fd301bcf621aeab06fc4e5789e64a226970aef38d4b3b006);
    }

    function _word(bytes memory d, uint256 i) internal pure returns (bytes32 w) {
        assembly { w := mload(add(add(d, 0x20), mul(i, 0x20))) }
    }

    function _admin(bytes32 id) internal view returns (address) {
        (bool ok, bytes memory r) = BUILDERS.staticcall(abi.encodeWithSignature("subnets(bytes32)", id));
        if (!ok || r.length < 64) return address(0);
        return address(uint160(uint256(_word(r, 1))));
    }

    function _subClaimable(bytes32 id) internal view returns (uint256) {
        (bool ok, bytes memory r) = BUILDERS.staticcall(
            abi.encodeWithSignature("getCurrentSubnetRewards(bytes32)", id));
        return ok && r.length >= 32 ? uint256(_word(r, 0)) : 0;
    }

    function _tryAggregate() internal view returns (bool ok, uint256 value) {
        bytes memory r;
        (ok, r) = BUILDERS.staticcall(abi.encodeWithSignature("getCurrentSubnetsRewards()"));
        value = (ok && r.length >= 32) ? uint256(_word(r, 0)) : 0;
    }

    function _ledger() internal view returns (uint256 distributed, uint256 undistributed, uint256 claimed) {
        (bool ok, bytes memory r) = BUILDERS.staticcall(abi.encodeWithSignature("allSubnetsDataV4()"));
        require(ok && r.length >= 128, "allSubnetsDataV4 read failed");
        distributed = uint256(_word(r, 0));
        undistributed = uint256(_word(r, 1));
        claimed = uint256(_word(r, 2));
    }

    function _networkShare() internal view returns (uint256) {
        (bool ok, bytes memory r) = BUILDERS.staticcall(abi.encodeWithSignature("networkShare()"));
        require(ok, "networkShare read failed");
        return uint256(_word(r, 0));
    }

    function _sweep() internal returns (uint256 paid, uint256 okCount, uint256 failCount) {
        for (uint256 i = 0; i < ids.length; i++) {
            address admin = _admin(ids[i]);
            if (admin == address(0)) continue;
            uint256 before = mor.balanceOf(admin);
            vm.prank(admin);
            (bool ok, ) = BUILDERS.call(abi.encodeWithSignature("claim(bytes32,address)", ids[i], admin));
            if (ok) { paid += mor.balanceOf(admin) - before; okCount++; } else { failCount++; }
        }
    }

    /// A. the two getters documenting the same quantity disagree
    function test_A_gettersDisagree() public {
        uint256 sumSub;
        for (uint256 i = 0; i < ids.length; i++) sumSub += _subClaimable(ids[i]);
        (bool ok, uint256 agg) = _tryAggregate();
        (uint256 dist, , uint256 claimed) = _ledger();

        console2.log("subnets                          :", ids.length);
        console2.log("SUM(getCurrentSubnetRewards)     :", sumSub);
        console2.log("getCurrentSubnetsRewards()       :", agg);
        console2.log("distributedRewards - claimed     :", dist - claimed);
        console2.log("overstatement                    :", sumSub - agg);
        console2.log("ratio x1e18                      :", sumSub * 1e18 / agg);

        assertTrue(ok, "aggregate reverted on pristine fork");
        assertGt(sumSub, agg, "getters agree - no finding");
    }

    /// B. legitimate claims push cumulative payouts past cumulative accruals
    function test_B_claimedExceedsDistributed() public {
        (uint256 distBefore, , uint256 claimedBefore) = _ledger();
        (bool okB, uint256 aggB) = _tryAggregate();
        uint256 sumSub;
        for (uint256 i = 0; i < ids.length; i++) sumSub += _subClaimable(ids[i]);
        uint256 treasBefore = mor.balanceOf(TREASURY);

        (uint256 paid, uint256 okc, uint256 failc) = _sweep();

        (uint256 distAfter, , uint256 claimedAfter) = _ledger();
        (bool okA, ) = _tryAggregate();

        console2.log("=== BEFORE ===");
        console2.log("distributedRewards               :", distBefore);
        console2.log("claimedRewards                   :", claimedBefore);
        console2.log("ledger outstanding               :", distBefore - claimedBefore);
        console2.log("SUM(getCurrentSubnetRewards)     :", sumSub);
        console2.log("getCurrentSubnetsRewards()       :", aggB);
        console2.log("treasury MOR                     :", treasBefore);
        console2.log("=== SWEEP ===");
        console2.log("claims ok / reverted             :", okc, failc);
        console2.log("TOTAL MOR PAID OUT               :", paid);
        console2.log("treasury after                   :", mor.balanceOf(TREASURY));
        console2.log("=== AFTER ===");
        console2.log("distributedRewards               :", distAfter);
        console2.log("claimedRewards                   :", claimedAfter);
        console2.log("claimed > distributed            :", claimedAfter > distAfter);
        console2.log("OVER-ISSUANCE                    :", claimedAfter > distAfter ? claimedAfter - distAfter : 0);
        console2.log("aggregate getter still works     :", okA);

        assertGt(claimedAfter, distAfter, "claimedRewards did not exceed distributedRewards");
    }

    /// C. cumulative claims exceed the ENTIRE reward emission allocated to Builders since the
    /// V4 diamond cut. `_emissionBudget()` uses the V4 cut timestamp read from Base
    /// (block 39654132 -> 2025-12-18 22:40:11 UTC).
    function test_C_claimsExceedEmissionBudget() public {
        uint256 cutTs = 1766097611;
        uint256 forkTs = block.timestamp;
        uint256 em = rp.getPeriodRewards(POOL_ID, uint128(cutTs), uint128(forkTs));
        uint256 share = _networkShare();
        uint256 budget = em * share / PRECISION;

        (uint256 distBefore, , uint256 claimedBefore) = _ledger();
        (uint256 paid, uint256 okc, uint256 failc) = _sweep();
        (uint256 distAfter, , uint256 claimedAfter) = _ledger();

        console2.log("V4 cut timestamp                 :", cutTs);
        console2.log("fork timestamp                   :", forkTs);
        console2.log("pool 3 emission over V4 era      :", em);
        console2.log("networkShare                     :", share);
        console2.log("BUILDERS EMISSION BUDGET         :", budget);
        console2.log("");
        console2.log("claimedRewards before            :", claimedBefore);
        console2.log("claims ok / reverted             :", okc, failc);
        console2.log("TOTAL PAID OUT                   :", paid);
        console2.log("claimedRewards after             :", claimedAfter);
        console2.log("");
        console2.log("claimed AFTER - budget           :", claimedAfter > budget ? claimedAfter - budget : 0);
        console2.log("paid - ledger outstanding        :", paid > (distBefore - claimedBefore) ? paid - (distBefore - claimedBefore) : 0);
        console2.log("claimed after - distributed after:", claimedAfter > distAfter ? claimedAfter - distAfter : 0);

        assertGt(claimedAfter, budget, "claims stayed inside the emission budget");
    }

    /// D. control - total extracted is order dependent at the same block
    function test_D_orderDependence() public {
        (uint256 dist, , uint256 claimed) = _ledger();
        uint256 ledger = dist - claimed;

        (uint256 paidFwd, , ) = _sweep();

        vm.createSelectFork(vm.envString("BASE_RPC"), FORK_BLOCK);
        uint256 n = ids.length;
        uint256 paidRev;
        for (uint256 k = 0; k < n; k++) {
            uint256 i = n - 1 - k;
            address admin = _admin(ids[i]);
            if (admin == address(0)) continue;
            uint256 before = mor.balanceOf(admin);
            vm.prank(admin);
            (bool ok, ) = BUILDERS.call(abi.encodeWithSignature("claim(bytes32,address)", ids[i], admin));
            if (ok) paidRev += mor.balanceOf(admin) - before;
        }

        console2.log("ledger owed              :", ledger);
        console2.log("paid forward             :", paidFwd);
        console2.log("paid reverse             :", paidRev);
        console2.log("difference               :", paidRev > paidFwd ? paidRev - paidFwd : paidFwd - paidRev);

        assertTrue(paidFwd != paidRev, "order independent - no finding");
    }
}
