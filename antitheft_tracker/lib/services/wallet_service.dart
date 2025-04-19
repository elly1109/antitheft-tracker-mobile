// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:http/http.dart' as http;
// import 'package:url_launcher/url_launcher.dart';
// import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
// import 'package:web3dart/web3dart.dart';
// import 'package:qr_flutter/qr_flutter.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// class WalletService {
//   Web3App? _web3App;
//   String? ethAddress;
//   Web3Client? _web3client;
//   DeployedContract? _contract;
//   EthereumAddress? _contractAddress;
//   SessionData? _sessionData;
//
//   static bool _isSimulator = kDebugMode && defaultTargetPlatform == TargetPlatform.iOS;
//
//   // SharedPreferences for persistent storage
//   late SharedPreferences _prefs;
//
//   Future<void> init() async {
//     _prefs = await SharedPreferences.getInstance();
//
//     // Initialize Web3App
//     _web3App = await Web3App.createInstance(
//       projectId: dotenv.env['REOWN_PROJECT_ID']!,
//       metadata: const PairingMetadata(
//         name: 'AntiTheft Tracker',
//         description: 'Track devices on blockchain',
//         url: 'https://example.com',
//         icons: [],
//       ),
//       relayUrl: 'wss://relay.walletconnect.org',
//     );
//
//     // Initialize Web3Client
//     _web3client = Web3Client(
//       dotenv.env['INFURA_URL']!,
//       http.Client(),
//     );
//     _contractAddress = EthereumAddress.fromHex(dotenv.env['CONTRACT_ADDRESS']!);
//
//     const abi = '''[
//       {"inputs":[{"internalType":"string","name":"deviceId","type":"string"}],"name":"registerDevice","outputs":[],"stateMutability":"nonpayable","type":"function"},
//       {"inputs":[{"internalType":"string","name":"deviceId","type":"string"}],"name":"reportStolen","outputs":[],"stateMutability":"nonpayable","type":"function"},
//       {"inputs":[{"internalType":"string","name":"deviceId","type":"string"},{"internalType":"address","name":"newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},
//       {"inputs":[{"internalType":"string","name":"deviceId","type":"string"}],"name":"checkStolen","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"},
//       {"inputs":[{"internalType":"string","name":"deviceId","type":"string"}],"name":"getOwner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},
//       {"anonymous":false,"inputs":[{"indexed":false,"internalType":"string","name":"deviceId","type":"string"},{"indexed":false,"internalType":"address","name":"owner","type":"address"}],"name":"DeviceRegistered","type":"event"},
//       {"anonymous":false,"inputs":[{"indexed":false,"internalType":"string","name":"deviceId","type":"string"}],"name":"DeviceStolen","type":"event"},
//       {"anonymous":false,"inputs":[{"indexed":false,"internalType":"string","name":"deviceId","type":"string"},{"indexed":false,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferred","type":"event"}
//     ]''';
//
//     _contract = DeployedContract(
//       ContractAbi.fromJson(abi, 'DeviceRegistry'),
//       _contractAddress!,
//     );
//
//     // Verify contract deployment
//     final code = await _web3client!.getCode(_contractAddress!);
//     if (code.isEmpty) {
//       throw Exception('Contract not deployed at $_contractAddress');
//     }
//
//     // Session listeners
//     _web3App!.onSessionConnect.subscribe((SessionConnect? args) {
//       _sessionData = args?.session;
//       ethAddress = _sessionData?.namespaces['eip155']?.accounts.first.split(':').last;
//       _prefs.setString('ethAddress', ethAddress!);
//     });
//
//     _web3App!.onSessionDelete.subscribe((args) {
//       ethAddress = null;
//       _sessionData = null;
//       _prefs.remove('ethAddress');
//     });
//
//     // Check existing sessions
//     ethAddress = _prefs.getString('ethAddress');
//     if (ethAddress != null) {
//       debugPrint('Found existing session with address: $ethAddress');
//     }
//   }
//
//   Future<String?> connect() async {
//     if (_web3App == null) await init();
//     if (_sessionData == null) {
//       try {
//         debugPrint('Initiating WalletConnect connection');
//         final connectResponse = await _web3App!.connect(
//           requiredNamespaces: {
//             'eip155': const RequiredNamespace(
//               chains: ['eip155:11155111'],
//               methods: ['eth_sendTransaction', 'eth_sign'],
//               events: ['chainChanged', 'accountsChanged'],
//             ),
//           },
//         );
//         debugPrint('Generated WalletConnect URI: ${connectResponse.uri}');
//
//         if (_isSimulator) {
//           debugPrint(
//               'Running in iOS simulator. Paste this URI in MetaMask on your physical mobile device:\n${connectResponse.uri}\n'
//                   'Or generate a QR code and scan it.');
//         } else {
//           final launched = await launchUrl(
//             connectResponse.uri!,
//             mode: LaunchMode.externalApplication,
//           );
//           if (!launched) {
//             debugPrint('Failed to launch URI. Please open MetaMask and paste: ${connectResponse.uri}');
//             throw Exception('Could not launch WalletConnect URI');
//           }
//         }
//
//         debugPrint('Waiting for session approval...');
//         _sessionData = await connectResponse.session.future.timeout(
//           const Duration(seconds: 120),
//           onTimeout: () {
//             debugPrint('Session connection timed out after 120 seconds');
//             throw Exception('Session connection timed out');
//           },
//         );
//         ethAddress = _sessionData!.namespaces['eip155']!.accounts.first.split(':').last;
//         _prefs.setString('ethAddress', ethAddress!);
//         debugPrint('Connected with address: $ethAddress');
//       } catch (e) {
//         debugPrint('WalletConnect error: $e');
//         throw Exception('WalletConnect failed: $e');
//       }
//     }
//     return ethAddress;
//   }
//
//   Future<void> registerDevice(String deviceId) async {
//     if (_web3App == null || _sessionData == null || ethAddress == null || _contract == null || _contractAddress == null) {
//       debugPrint('Wallet not connected or missing required data.');
//       throw Exception('Wallet not connected');
//     }
//
//     if (deviceId.isEmpty) {
//       debugPrint('Invalid deviceId: empty');
//       throw Exception('Device ID cannot be empty');
//     }
//
//     try {
//       final function = _contract!.function('registerDevice');
//       final data = function.encodeCall([deviceId]);
//
//       // Estimate gas
//       final gasEstimate = await _web3client!.estimateGas(
//         sender: EthereumAddress.fromHex(ethAddress!),
//         to: _contractAddress,
//         data: data,
//       );
//
//       final gasPrice = await _web3client!.getGasPrice();
//       final txParams = {
//         'from': ethAddress,
//         'to': _contractAddress!.hex,
//         'data': '0x${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
//         'gas': '0x${(gasEstimate.toInt() * 1.2).toInt().toRadixString(16)}',
//         'gasPrice': '0x${gasPrice.getInWei.toInt().toRadixString(16)}',
//       };
//
//       final txHash = await _web3App!.request(
//         topic: _sessionData!.topic,
//         chainId: 'eip155:11155111',
//         request: SessionRequestParams(
//           method: 'eth_sendTransaction',
//           params: [txParams],
//         ),
//       );
//
//       debugPrint('Transaction sent successfully: $txHash');
//       await _checkTransactionStatus(txHash);
//     } catch (e) {
//       debugPrint('Transaction error: $e');
//       throw Exception('Failed to register device: $e');
//     }
//   }
//
//   Future<void> _checkTransactionStatus(String txHash) async {
//     // Poll for transaction receipt
//     bool isConfirmed = false;
//     while (!isConfirmed) {
//       await Future.delayed(const Duration(seconds: 5));
//       final receipt = await _web3client!.getTransactionReceipt(txHash);
//       if (receipt != null) {
//         isConfirmed = true;
//         debugPrint('Transaction confirmed: $txHash');
//       }
//     }
//   }
//
//   Future<void> disconnect() async {
//     if (_web3App != null && _sessionData != null) {
//       try {
//         await _web3App!.disconnectSession(
//           topic: _sessionData!.topic,
//           reason: WalletConnectError(
//             code: 6000,
//             message: 'User disconnected',
//           ),
//         );
//         ethAddress = null;
//         _sessionData = null;
//         _prefs.remove('ethAddress');
//         debugPrint('Wallet disconnected');
//       } catch (e) {
//         debugPrint('Disconnect error: $e');
//       }
//     }
//   }
//
//   // QR code widget for WalletConnect URI
//
//   Widget generateQRCode(String uri) {
//     return QrImageView(
//       data: uri,
//       version: QrVersions.auto,
//       size: 200.0,
//       gapless: false,
//     );
//   }
//
// }
