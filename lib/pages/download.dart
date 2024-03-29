import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:stendmobile/utils/format_bytes.dart';
import 'package:stendmobile/utils/format_date.dart';
import 'package:stendmobile/utils/show_snackbar.dart';
import 'package:stendmobile/utils/smash_account.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get_storage/get_storage.dart';
import 'package:html/parser.dart';
import 'package:tuple/tuple.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:dio/dio.dart';

final dio = Dio(BaseOptions(
  headers: {
    'User-Agent': 'StendMobile-Flutter/${Platform.operatingSystem}',
  },
  contentType: Headers.jsonContentType,
  connectTimeout: const Duration(milliseconds: 7000),
  sendTimeout: const Duration(milliseconds: 7000),
  receiveTimeout: const Duration(milliseconds: 7000),
  validateStatus: (status) {
    return true;
  }
));

class DownloadDialog extends StatefulWidget {
  final String content;
  final String? fileType;
  final double? value;

  const DownloadDialog({Key? key, required this.content, this.value, this.fileType}) : super(key: key);

  @override
  DownloadDialogState createState() => DownloadDialogState();
}

class DownloadDialogState extends State<DownloadDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: const Text("Téléchargement"),
      content: Column(
        mainAxisSize: MainAxisSize.min,

        children: [
          Platform.isAndroid ? Text(widget.content, textAlign: TextAlign.center) : const SizedBox(),

          const SizedBox(height: 12.0),
          LinearProgressIndicator(value: widget.value),
          const SizedBox(height: 12.0),
          Platform.isAndroid && widget.fileType != null ? Text("Fichier : ${widget.fileType!}") : Platform.isIOS ? Text(widget.content) : const SizedBox(),
        ],
      ),
    );
  }
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({Key? key}) : super(key: key);

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  late GetStorage box;

  late TextEditingController urlController;

  QRViewController? qrController;
  String? lastScannedCode;

  final StreamController<Tuple3<String, double?, String?>> downloadAlertStreamController = StreamController<Tuple3<String, double?, String?>>.broadcast();
  Tuple3<String, double?, String?> downloadAlertTupple = const Tuple3("Préparation...", null, null);

  List historic = [];
  List tips = [];

  @override
  void initState() {
    box = GetStorage();
    urlController = TextEditingController();

    setState(() {
      historic = box.read('historic') ?? [];
      if (box.read('tips') != null) {
        tips = box.read('tips');
      } else {
        tips = [
          "Télécharger des fichiers depuis des services tiers comme WeTransfer, Smash, TikTok ou YouTube.",
          "Appuyer longuement sur un transfert dans l'historique pour le partager, ou appuyer simplement pour le retélécharger.",
          "Personnaliser la page d'accueil et l'apparence de l'application depuis les réglages."
        ];
        box.write('tips', tips);
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    urlController.dispose();
    downloadAlertStreamController.close();

    super.dispose();
  }

  void startDownload() async {
    // Définir des variables importantes
    String service = 'stend';
    String apiUrl = '';
    String downloadKey = urlController.text;
    String secondKey = '';
    String token = '';

    // Si l'utilisateur n'a rien entré, on arrête là
    if (downloadKey.isEmpty) {
      showSnackBar(context, "Veuillez entrer un lien ou une clé de partage");
      return;
    }

    // Créer un client HTTP
    final http.Client client = http.Client();

    // Si l'input de l'utilisateur contient un espace, on cherche un lien dans le texte
    if (downloadKey.contains(' ')) {
      RegExp regExp = RegExp(r'(https?://\S+)');
      var matches = regExp.allMatches(downloadKey);
      if (matches.isNotEmpty) {
        downloadKey = matches.first.group(0)!;
      }
    }

    // On détermine le service utilisé si c'est pas Stend
    if (downloadKey.startsWith('https://transfert.free.fr/') || downloadKey.startsWith('http://transfert.free.fr/')) {
      service = 'free';
    }
    else if (downloadKey.startsWith('https://we.tl/') || downloadKey.startsWith('http://we.tl/') || downloadKey.startsWith('https://wetransfer.com/downloads/') || downloadKey.startsWith('http://wetransfer.com/downloads/')) {
      service = 'wetransfer';
    }
    else if (downloadKey.startsWith("https://fromsmash.com/") || downloadKey.startsWith('http://fromsmash.com/')) {
      service = 'smash';
    }
    else if (downloadKey.startsWith('https://www.swisstransfer.com/d/') || downloadKey.startsWith('http://www.swisstransfer.com/d/') || downloadKey.startsWith('https://swisstransfer.com/d/') || downloadKey.startsWith('http://swisstransfer.com/d/')) {
      service = 'swisstransfer';
    }
    else if (downloadKey.startsWith('https://bilibili.com/') || downloadKey.startsWith('https://bilibili.tv/') || downloadKey.startsWith('https://twitter.com/') || downloadKey.startsWith('https://mobile.twitter.com/') || downloadKey.startsWith('https://x.com/') || downloadKey.startsWith('https://vxtwitter.com/') || downloadKey.startsWith('https://fixvx.com/') || downloadKey.startsWith('https://youtube.com/watch?v=') || downloadKey.startsWith('https://www.youtube.com/watch?v=') || downloadKey.startsWith('https://m.youtube.com/watch?v=') || downloadKey.startsWith('https://youtu.be/') || downloadKey.startsWith('https://youtube.com/embed/') || downloadKey.startsWith('https://youtube.com/watch/') || downloadKey.startsWith('https://tumblr.com/') || downloadKey.startsWith('https://www.tumblr.com/') || downloadKey.startsWith('https://tiktok.com/') || downloadKey.startsWith('https://www.tiktok.com/') || downloadKey.startsWith('https://vm.tiktok.com/') || downloadKey.startsWith('https://vt.tiktok.com/') || downloadKey.startsWith('https://vimeo.com/') || downloadKey.startsWith('https://soundcloud.com/') || downloadKey.startsWith('https://on.soundcloud.com/') || downloadKey.startsWith('https://m.soundcloud.com/') || downloadKey.startsWith('https://instagram.com/') || downloadKey.startsWith('https://www.instagram.com/') || downloadKey.startsWith('https://www.vine.co/v/') || downloadKey.startsWith('https://vine.co/v/') || downloadKey.startsWith('https://pinterest.com/') || downloadKey.startsWith('https://www.pinterest.com/') || downloadKey.startsWith('https://pinterest.fr/') || downloadKey.startsWith('https://www.pinterest.fr/') || downloadKey.startsWith('https://pin.it/') || downloadKey.startsWith('https://streamable.com/') || downloadKey.startsWith('https://www.streamable.com/') || downloadKey.startsWith('https://twitch.tv/') || downloadKey.startsWith('https://clips.twitch.tv/') || downloadKey.startsWith('https://www.twitch.tv/') || downloadKey.startsWith('https://dailymotion.com/video/') || downloadKey.startsWith('https://www.dailymotion.com/video/') || downloadKey.startsWith('https://dai.ly/')) {
      service = 'cobalt';
    }
    else if (downloadKey.startsWith('https://mediafire.com/file/') || downloadKey.startsWith('https://www.mediafire.com/file/')) {
      service = 'mediafire';
    }

    // Afficher un avertissement sur un service tiers
    if (service != 'stend') {
      var alreadyWarned = box.read('warnedAboutThirdPartyService') ?? false;
      if (!alreadyWarned) {
        box.write('warnedAboutThirdPartyService', true);
        await showAdaptiveDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog.adaptive(
              title: const Text("Service tiers"),
              content: const Text("Vous êtes sur le point de télécharger un fichier depuis un service tiers. Certaines fonctionnalités peuvent ne pas être implémentées ou ne pas fonctionner correctement."),
              actions: [
                TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.pop(context);
                  },
                  child: const Text("Continuer"),
                ),
              ],
            );
          }
        );
      }
    }

    // Afficher une alerte
    if (!mounted) return;
    downloadAlertTupple = const Tuple3("Préparation...", null, null);
    showAdaptiveDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return StreamBuilder(
          stream: downloadAlertStreamController.stream,
          initialData: downloadAlertTupple,
          builder: (BuildContext context, AsyncSnapshot snapshot) {
            String content = snapshot.data.item1;
            double? value = snapshot.data.item2;
            String? fileType = snapshot.data.item3;
            return WillPopScope(
              child: DownloadDialog(content: content, value: value, fileType: fileType),
              onWillPop: () async {
                return false;
              },
            );
          }
        );
      }
    );

    // Client Stend - on obtient le lien de l'API
    if (service == 'stend') {
      if (downloadKey.startsWith("http://") || downloadKey.startsWith("https://")) {
        Response response;

        try {
          // Faire une requête pour obtenir l'URL de l'API
          response = await dio.get(downloadKey, 
            options: Options(
              followRedirects: false,
              validateStatus: (status) {
                return status! < 500;
              }
            )
          );
          while (response.isRedirect) {
            String location = response.headers.value('location')!;
            downloadKey = response.requestOptions.uri.toString();
            if (location.startsWith("/")) location = '${downloadKey.split("/")[0]}//${downloadKey.split("/")[2]}$location';
            if (location.endsWith('=')) location = location.substring(0, location.length - 1);
            response = await dio.get(location, 
              options: Options(
                followRedirects: false,
                validateStatus: (status) {
                  return status! < 500;
                }
              )
            );
          }
        } catch (e) {
          debugPrint(e.toString());
          if (!mounted) return;
          Navigator.pop(context);
          showSnackBar(context, "Le lien entré n'est pas accessible, vérifier votre connexion");
          return;
        }

        // Obtenir ce qu'on a besoin d'obtenir
        if (!mounted) return;
        if (response.statusCode == 200 && response.data.isNotEmpty) {
          try {
            apiUrl = response.data.split('apibaseurl="')[1].split('"')[0];
            downloadKey = response.requestOptions.uri.toString().split('?')[1].split('&')[0];
          } catch (e) {
            debugPrint(e.toString());
            Navigator.pop(context);
            showSnackBar(context, "Nous n'avons pas pu obtenir le infos sur le serveur");
            return;
          }
        }
        else {
          Navigator.pop(context);
          showSnackBar(context, "La page ne contient pas les infos sur le serveur");
          return;
        }
      }

      // Sinon, on utilise l'URL de l'API par défaut
      if (apiUrl.length < 3) {
        apiUrl = box.read("apiInstanceUrl") ?? '';
        if (apiUrl.isEmpty) {
          if (!mounted) return;
          Navigator.pop(context);
          showSnackBar(context, "L'API n'a pas été configurée depuis les réglages");
          return;
        }
      }
    }

    // Free transfert - obtenir la clé de téléchargement
    else if (service == 'free') {
      if (downloadKey.endsWith("/")) downloadKey = downloadKey.substring(0, downloadKey.length - 1);
      downloadKey = downloadKey.split("/").last;
    }

    // Raccourci WeTransfer - obtenir les clés importantes
    else if (service == 'wetransfer' && (downloadKey.startsWith("https://we.tl/") || downloadKey.startsWith("http://we.tl/"))) {
      // Faire une requpete pour obtenir le lien non raccourci
      Response response = await dio.get(downloadKey, 
        options: Options(
          followRedirects: false,
          validateStatus: (status) {
            return status! < 500;
          }
        )
      );
      while (response.isRedirect) {
        String location = response.headers.value('location')!;
        if (location.startsWith("/")) location = '${downloadKey.split("/")[0]}//${downloadKey.split("/")[2]}$location';
        response = await dio.get(location, 
          options: Options(
            followRedirects: false,
            validateStatus: (status) {
              return status! < 500;
            }
          )
        );
      }

      // Obtenir ce qu'on a besoin d'obtenir
      if (!mounted) return;
      if (response.statusCode == 200 && response.data.isNotEmpty) {
        downloadKey = response.requestOptions.uri.toString();
        secondKey = downloadKey.split("/").last;
        downloadKey = downloadKey.split("/").reversed.skip(1).first;
      }
      else {
        Navigator.pop(context);
        showSnackBar(context, "Nous n'avons pas pu obtenir l'URL après redirection");
        return;
      }
    }

    // WeTransfer - obtenir les clés importantes
    else if (service == 'wetransfer') {
      if (downloadKey.endsWith("/")) downloadKey = downloadKey.substring(0, downloadKey.length - 1);
      secondKey = downloadKey.split("/").last;
      downloadKey = downloadKey.split("/").reversed.skip(1).first;
      if (downloadKey.isEmpty || secondKey.isEmpty) {
        if (!mounted) return;
        Navigator.pop(context);
        showSnackBar(context, "Impossible de récupérer les clés de téléchargement");
        return;
      }
    }

    // Smash - obtenir des infos importantes
    else if (service == 'smash') {
      if (downloadKey.endsWith("/")) downloadKey = downloadKey.substring(0, downloadKey.length - 1);
      downloadKey = downloadKey.split("/").last;

      token = await getSmashAccount();
      if (token.startsWith('err_')) {
        if (!mounted) return;
        Navigator.pop(context);
        showSnackBar(context, token.substring(4));
        return;
      }
    }

    // Swisstransfer - obtenir la clé de téléchargement
    else if (service == 'swisstransfer') {
      if (downloadKey.endsWith("/")) downloadKey = downloadKey.substring(0, downloadKey.length - 1);
      downloadKey = downloadKey.split("/").last;
      if (downloadKey.isEmpty) {
        if (!mounted) return;
        Navigator.pop(context);
        showSnackBar(context, "Impossible de récupérer la clé de téléchargement");
        return;
      }
    }

    // Cobalt, Mediafire - on a rien à faire

    // Si on a pas de clé de téléchargement, on arrête là
    if (downloadKey.isEmpty) {
      if (!mounted) return;
      Navigator.pop(context);
      showSnackBar(context, "Aucune clé de téléchargement n'est spécifiée");
      return;
    }

    // Vérifier que l'application puisse télécharger le fichier
    if (Platform.isAndroid) {
      final permissionStatus = await Permission.manageExternalStorage.status;
      if (permissionStatus.isDenied) {
        await Permission.manageExternalStorage.request();

        if (permissionStatus.isDenied) {
          if (!mounted) return;
          Navigator.pop(context);
          showSnackBar(context, "L'application a besoin de gérer tous les fichiers pour pouvoir en télécharger");
          return;
        }
      } else if (permissionStatus.isPermanentlyDenied) {
        if (!mounted) return;
        Navigator.pop(context);
        showSnackBar(context, "L'application a besoin de gérer tous les fichiers pour pouvoir en télécharger");
        return;
      }
    }

    // Enlever le slash à la fin de l'URL de l'API s'il y en a un
    if (apiUrl.endsWith("/")) {
      apiUrl = apiUrl.substring(0, apiUrl.length - 1);
    }

    // Changer l'alerte
    downloadAlertTupple = const Tuple3("Obtention des infos...", null, null);

    // On récupère les informations du transfert
    http.Response transfertInfo;
    try {
      if (service == 'stend') { // Support manquant : rien
        transfertInfo = await http.get(Uri.parse("$apiUrl/files/info?sharekey=$downloadKey"));
      } else if (service == 'free') { // Support manquant : transferts protégés par mot de passe
        transfertInfo = await http.get(Uri.parse("https://api.scw.iliad.fr/freetransfert/v2/transfers/$downloadKey"));
      } else if (service == 'wetransfer') { // Support manquant : transferts protégés par mot de passe ; les fichiers uploadé à partir d'un dossier peuvent être corrompus (problème avec l'API)
        transfertInfo = await http.post(Uri.parse("https://wetransfer.com/api/v4/transfers/$downloadKey/prepare-download"), body: json.encode({ "security_hash": secondKey }), headers: { "Content-Type": "application/json" });
      } else if (service == 'smash') { // Support manquant : transferts protégés par mot de passe
        var transfertRegion = await http.get(Uri.parse("https://link.fromsmash.co/target/fromsmash.com%2F$downloadKey?version=10-2019"), headers: { "Authorization": token });

        final Map<String, dynamic> transfertRegionJson;
        try {
          transfertRegionJson = json.decode(utf8.decode(transfertRegion.bodyBytes));
        } catch (e) {
        if (!mounted) return;
          Navigator.pop(context);
          debugPrint(e.toString());
          showSnackBar(context, "Impossible de récupérer la région du transfert");
          return;
        }

        if (transfertRegionJson['target']['region'] == null) {
          if (!mounted) return;
          Navigator.pop(context);
          showSnackBar(context, "L'API n'a pas retourné la région du transfert");
          return;
        }

        transfertInfo = await http.get(Uri.parse("https://transfer.${transfertRegionJson['target']['region']}.fromsmash.co/transfer/$downloadKey/files/preview?version=07-2020"), headers: { "Authorization": token });
      } else if (service == 'swisstransfer') { // Support manquant : transferts protégés par mot de passe
        transfertInfo = await http.get(Uri.parse("https://www.swisstransfer.com/api/links/$downloadKey"), headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" });
      } else if (service == 'cobalt') { // Support manquant : quelques tests à faire ; certains services sont manquants ; picker (plusieurs médias)
        // Note : l'API Cobalt original ne retourne pas le nom du ƒichier dans l'endpoint principal, il faut donc utiliser une version modifiée
        transfertInfo = await http.post(Uri.parse("https://cobalt.johanstick.fr/api/json"), body: json.encode({ "url": downloadKey, "vQuality": "max", "aFormat": "best", "filenamePattern": "pretty", "isNoTTWatermark": true, "isTTFullAudio": true }), headers: { "Content-Type": "application/json", "Accept": "application/json" } );
      } else if (service == 'mediafire') { // Support manquant : dossiers
        var transfertInfoPage = await http.get(Uri.parse(downloadKey));
        var transfertInfoHtml = parse(transfertInfoPage.body);
        var fileName = transfertInfoHtml.querySelector('div.filename')?.text;
        var downloadLink = transfertInfoHtml.querySelector('a#downloadButton')?.attributes['href'];
        transfertInfo = http.Response(json.encode({ "fileName": fileName, "downloadLink": downloadLink }), 200);
      } else {
        if (!mounted) return;
        Navigator.pop(context);
        showSnackBar(context, "Ce service n'est pas supporté. Cela ne devrait pas arrivé. Signalez ce problème");
        return;
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      debugPrint(e.toString());
      showSnackBar(context, "Impossible de récupérer les infos via l'API");
      return;
    }

    // On parse en JSON
    if (!mounted) return;
    final Map<String, dynamic> transfertInfoJson;
    try {
      transfertInfoJson = json.decode(utf8.decode(transfertInfo.bodyBytes));
    } catch (e) {
      Navigator.pop(context);
      debugPrint(e.toString());
      showSnackBar(context, "L'API n'a pas retourné des informations valides");
      return;
    }

    // On vérifie si on a une erreur dans le JSON
    if (transfertInfoJson.containsKey("message") || transfertInfoJson.containsKey("text") || transfertInfoJson.containsKey("error") || (transfertInfoJson.containsKey("status") && transfertInfoJson["status"] == "error")) {
      Navigator.pop(context);
      debugPrint(transfertInfoJson.toString());
      showSnackBar(context, (transfertInfoJson["message"] == 'Forbidden' ? "Ce transfert n'a pas pu être obtenu en raison d'une autorisation manquante (transfert protégé ?)" : transfertInfoJson["message"] == "Object not found" || transfertInfoJson["message"] == "Transfer not found" || transfertInfoJson["message"] == "Not Found" ? "Le transfert est introuvable, vérifier l'URL" : transfertInfoJson["message"]) ?? transfertInfoJson["text"] ?? transfertInfoJson["error"] ?? "Impossible de récupérer les infos du transfert");
      return;
    }

    // On vérifie si on a une erreur dans le statut de la requête
    if (transfertInfo.statusCode != 200) {
      if (!mounted) return;
      Navigator.pop(context);
      showSnackBar(context, "L'API n'a pas retourné d'infos avec succès");
      return;
    }

    // Vérification additionnelle pour les WeTransfer (protégé par mdp)
    if (service == 'wetransfer' && transfertInfoJson["password_protected"] == true) {
      Navigator.pop(context);
      showSnackBar(context, "Stend ne supporte pas les liens protégés");
      return;
    }

    // Vérification additionnelle pour les SwissTransfer (protégé par mdp et autres avertissements)
    if (service == 'swisstransfer' && transfertInfoJson["data"] != null && transfertInfoJson["data"]["message"] != null) {
      Navigator.pop(context);
      showSnackBar(context, transfertInfoJson["data"]["message"]);
      return;
    }

    // On fait une variable initiale d'un array avec les transferts à télécharger
    List<Map<String, dynamic>> transfertsDownloads = [];

    // On passe sur chaque fichier pour obtenir leurs sous-informations
    if ((service == 'stend' && transfertInfoJson["isGroup"] == true && transfertInfoJson["groups"].isNotEmpty) || service == 'free' || service == 'wetransfer' || service == 'smash' || service == 'swisstransfer') {
      // Modifier le dialogue
      downloadAlertTupple = const Tuple3("Récupération des transferts...", null, null);
      downloadAlertStreamController.add(downloadAlertTupple);

      for (var transfert in (service == 'stend' ? transfertInfoJson["groups"] : transfertInfoJson["files"] ?? transfertInfoJson["items"] ?? transfertInfoJson["data"]["container"]["files"])) {
        // On fait une requête pour obtenir les informations du transfert
        http.Response subTransfertInfo;
        if (service == 'stend') {
          subTransfertInfo = await http.get(Uri.parse("$apiUrl/files/info?sharekey=$transfert"));
        } else if (service == 'wetransfer') {
          subTransfertInfo = await http.post(Uri.parse("https://wetransfer.com/api/v4/transfers/$downloadKey/download"), body: json.encode({ "security_hash": secondKey, "intent": "single_file", "file_ids": [transfert["id"]] }), headers: { "Content-Type": "application/json" });
        } else if (service == 'free') {
          subTransfertInfo = await http.get(Uri.parse("https://api.scw.iliad.fr/freetransfert/v2/files?transferKey=$downloadKey&path=${transfert["path"].toString().replaceAll(" ", "%20")}"));
        } else {
          subTransfertInfo = http.Response('', 200);
        }

        // On parse en JSON
        final Map<String, dynamic> subTransfertInfoJson;
        if(subTransfertInfo.body.isNotEmpty) {
          subTransfertInfoJson = json.decode(utf8.decode(subTransfertInfo.bodyBytes));
        }
        else {
          subTransfertInfoJson = transfert;
        }

        // Si on a une erreur, on ignore le transfert
        if (subTransfertInfoJson.containsKey("message") || subTransfertInfoJson.containsKey("error")) continue;

        // Vérification additionnelle pour les transferts Free
        if (service == 'free' && subTransfertInfoJson["url"] != null && subTransfertInfoJson["url"].toString().contains("/free-transfert.zip?X-Amz-Algorithm=")) {
          if (!mounted) return;
          showSnackBar(context, "Un des fichiers du transfert n'a pas pu être obtenu en raison d'un nom incorrect. Signalez le problème");
          continue;
        }

        // Normaliser le nom du fichier
        String fileName = transfert["name"] ?? transfert["path"] ?? transfert["fileName"] ?? transfert["filename"] ?? 'Aucun nom trouvé';
        if (fileName.contains("/")) fileName = fileName.split("/").last;

        // On ajoute le transfert à la liste
        if (service == 'stend') {
          transfertsDownloads.add(subTransfertInfoJson);
        } else if (service == 'free') {
          transfertsDownloads.add({
            "fileName": fileName,
            "fileSize": transfert["size"] != null ? int.parse(transfert["size"]) : 0,
            "downloadLink": subTransfertInfoJson["url"]
          });
        } else if (service == 'wetransfer') {
          transfertsDownloads.add({
            "fileName": fileName,
            "fileSize": transfert["size"],
            "downloadLink": subTransfertInfoJson["direct_link"]
          });
        } else if (service == 'smash') {
          transfertsDownloads.add({
            "fileName": fileName,
            "fileSize": transfert["size"],
            "downloadLink": transfert["download"]
          });
        } else if (service == 'swisstransfer') {
          transfertsDownloads.add({
            "fileName": fileName,
            "fileSize": transfert["fileSizeInBytes"],
            "downloadLink": "https://${transfertInfoJson["data"]["downloadHost"]}/api/download/${transfertInfoJson["data"]["linkUUID"]}/${transfert["UUID"]}"
          });
        }
      }
    }

    // Si on utilise Cobalt, on ajoute à la liste en fonction de la réponse
    else if (service == 'cobalt') {
      if (transfertInfoJson["status"] == "picker") {
        if (!mounted) return;
        showSnackBar(context, "Stend ne supporte pas les liens avec plusieurs médias");
        Navigator.pop(context);
        return;
      }

      if ((transfertInfoJson["status"] == "stream" || transfertInfoJson["status"] == "redirect") && transfertInfoJson.containsKey("url")) {
        transfertsDownloads.add({
          "fileName": transfertInfoJson["filename"] ?? "cobalt_unnamed_media",
          "downloadLink": transfertInfoJson["url"]
        });
      }
    }

    // Sinon, on ajoute le transfert à la liste
    else {
      transfertsDownloads.add(transfertInfoJson);
    }

    // Si on a pas de transferts à télécharger, on annule tout
    if (transfertsDownloads.isEmpty) {
      if (!mounted) return;
      showSnackBar(context, "Le groupe de transfert est vide ou a expiré");
      Navigator.pop(context);
      return;
    }

    // On détermine le chemin du fichier où télécharger
    String downloadDirectory = Platform.isAndroid ? '/storage/emulated/0/Download' : (await getApplicationDocumentsDirectory()).path;
    if (Platform.isIOS != true && box.read('downloadInSubFolder') == true) {
      // Créer le dossier s'il n'existe pas
      Directory('$downloadDirectory/Stend').createSync(recursive: true);

      // Changer le chemin du dossier
      downloadDirectory = '$downloadDirectory/Stend';
    }

    // On télécharge chaque transfert
    bool savedInGallery = false;
    for (var transfert in transfertsDownloads) {
      debugPrint(transfert.toString());
      // Vérifier les propriétés
      if (!transfert.containsKey("fileName") || !transfert.containsKey("downloadLink")) {
        if (!mounted) return;
        showSnackBar(context, "Un des transferts est mal formé (problème avec l'API ?)");
        Navigator.pop(context);
        return;
      }

      // Empêcher le nom du chemin d'aller en avant ou en arrière, et les caractères interdits
      String fileName = transfert["fileName"];
      String fileNamePath = fileName.replaceAll(RegExp(r'(\.\.)|(/)'), '').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

      // On récupère certaines infos
      int fileSize = transfert["fileSize"] ?? 0;
      String downloadLink = transfert["downloadLink"];
      String finalPath = path.join(downloadDirectory, fileNamePath);
      var fileType = transfert["fileType"]; // c'est ptet null donc on le met pas comme un String directement

      // Si le fichier existe déjà, on renomme celui qu'on télécharge
      if (File(finalPath).existsSync()) {
        int i = 1;
        while (File(finalPath).existsSync()) {
          finalPath = path.join(downloadDirectory, "${i}_$fileNamePath");
          i++;
        }
      }

      // On modifie l'alerte pour indiquer le nom du fichier
      downloadAlertTupple = Tuple3('$fileName${fileSize != 0 ? ' ― ${formatBytes(fileSize)}' : ''}', fileSize != 0 ? 0.0 : null, fileType);
      downloadAlertStreamController.add(downloadAlertTupple);

      // On télécharge le fichier
      final http.Request request = http.Request('GET', Uri.parse(downloadLink.startsWith("http") ? downloadLink : "$apiUrl$downloadLink"));
      final http.StreamedResponse response = await client.send(request);

      // On vérifie que le téléchargement a bien démarré
      await Future.delayed(const Duration(milliseconds: 200)); // jsp ça fix un bug quand on fait trop de requêtes trop vite
      if (response.statusCode != 200) {
        if (!mounted) return;
        showSnackBar(context, "Impossible de télécharger le fichier $fileName");
        Navigator.pop(context);
        return;
      }

      // On récupère le contenu de la réponse
      int? totalBytes = response.contentLength;
      int bytesDownloaded = 0;

      // On crée le fichier avec un nom de chemin qui ne permet pas de faire du path traversal
      final File file = File(finalPath);
      final IOSink sink = file.openWrite();

      await for (List<int> chunk in response.stream) {
        // On écrit le chunk dans le fichier
        sink.add(chunk);

        // On met à jour l'alerte et une variable pour le pourcentage si on a accès à la taille totale (indispo pour Cobalt par exemple)
        if (totalBytes != null || fileSize != 0) {
          bytesDownloaded += chunk.length;
          double downloadProgress = bytesDownloaded / (totalBytes ?? fileSize);
          downloadAlertTupple = Tuple3('$fileName${totalBytes != null || fileSize != 0 ? ' ― ${formatBytes(fileSize != 0 ? fileSize : totalBytes!)}' : ''}', downloadProgress, fileType);
          downloadAlertStreamController.add(downloadAlertTupple);
        }
      }

      // On ferme différents éléments
      await sink.flush();
      await sink.close();

      // Si on souhaite enregistrer dans la galerie et que c'est une image ou une vidéo
      if (box.read('saveMediasInGallery') == true) {
        // Déterminer le type de fichier
        var determinedFileType = fileName.split('.').last.toLowerCase();
        if (determinedFileType == 'jpeg' || determinedFileType == 'jpg' || determinedFileType == 'png' || determinedFileType == 'gif' || determinedFileType == 'webp') {
          determinedFileType = 'image';
        } else if (determinedFileType == 'mp4' || determinedFileType == 'mov' || determinedFileType == 'avi' || determinedFileType == 'mkv' || determinedFileType == 'webm') {
          determinedFileType = 'video';
        }

        // Si on a un type de fichier, on continue
        if (determinedFileType == 'image' || determinedFileType == 'video') {
          bool shouldContinue = false;

          // On vérifie les permissions
          final hasAccess = await Gal.hasAccess();
          if (!hasAccess) {
            await Gal.requestAccess();

            final hasAccess = await Gal.hasAccess();
            if (!hasAccess) {
              if (!mounted) return;
              showSnackBar(context, "La permission pour enregistrer dans la galerie a été refusée, le fichier se trouve dans le dossier téléchargement");
            } else {
              shouldContinue = true;
            }
          } else {
            shouldContinue = true;
          }

          // Si on a la permission, on continue
          if (shouldContinue) {
            try {
              // On enregistre le fichier dans la galerie
              if (determinedFileType == 'image') {
                await Gal.putImage(finalPath);
                savedInGallery = true;
              } else if (determinedFileType == 'video') {
                await Gal.putVideo(finalPath);
                savedInGallery = true;
              }

              // On supprime le fichier téléchargé
              await file.delete();
            } catch (e) {
              debugPrint(e.toString());
              if (!mounted) return;
              showSnackBar(context, "Impossible d'enregistrer le fichier dans la galerie");
            }
          }
        }
      }
    }

    // On ferme l'alerte
    lastScannedCode = null;
    if (!mounted) return;
    Navigator.pop(context);
    HapticFeedback.heavyImpact();
    showSnackBar(context, "${transfertsDownloads.length > 1 ? "${transfertsDownloads.length} fichiers ont été téléchargés" : "Le fichier a été téléchargé"}${savedInGallery ? " dans la galerie" : " dans vos téléchargements"}");
  }

	@override
	Widget build(BuildContext context) {
		return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              // Titre de la section
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Besoin de télécharger un fichier ?",

                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.brightness == Brightness.dark ? Colors.white : Colors.black,
                  )
                )
              ),

              const SizedBox(height: 18.0),

              // Demander l'url de téléchargement du fichier dans un input
              TextField(
                controller: urlController,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Lien ou clé de partage du transfert",
                  hintText: "stend.example.com/d?123456",
                  suffixIcon: IconButton(
                    icon: Icon(Platform.isIOS ? Icons.arrow_forward_ios : Icons.arrow_forward),
                    onPressed: () { startDownload(); }
                  ),
                ),
                onSubmitted: (String value) { startDownload(); },
              ),

              const SizedBox(height: 12.0),

              // Groupe de boutons pour définir une url rapidement
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        HapticFeedback.lightImpact();

                        // Lire le presse-papier
                        var data = await Clipboard.getData('text/plain');
                        var clipboard = data?.text;

                        // Si le presse-papier fait moins de 3 caractères ou plus de 256 caractères, on ne le prend pas en compte
                        if (clipboard == null || clipboard.length < 3 || clipboard.length > 256) {
                          if (!mounted) return;
                          showSnackBar(context, "Aucun lien valide dans le presse-papier");
                        }

                        // Mettre à jour l'input avec le presse-papier
                        else {
                          urlController.text = clipboard;
                          startDownload();
                        }
                      },
                      child: const Text("Presse papier"),
                    )
                  ),

                  const SizedBox(width: 12.0),

                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        HapticFeedback.lightImpact();

                        // Ouvrir une bottom sheet pour scanner un QR Code
                        showModalBottomSheet(
                          context: context,
                          builder: (BuildContext bc) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min, // Ajouté pour prendre le moins d'espace possible

                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: QRView(
                                      key: GlobalKey(debugLabel: 'QR'),
                                      formatsAllowed: const [BarcodeFormat.qrcode],
                                      overlay: QrScannerOverlayShape(
                                        borderRadius: 10,
                                        borderColor: Colors.white,
                                        borderLength: 30,
                                        borderWidth: 10,
                                        cutOutSize: 300,
                                      ),
                                      cameraFacing: box.read('cameraFacing') == 'Avant' ? CameraFacing.front : CameraFacing.back,
                                      onQRViewCreated: _onQRViewCreated,
                                    )
                                  )
                                ]
                              )
                            );
                          }
                        );
                      },
                      child: const Text("QR Code"),
                    )
                  )
                ],
              ),

              const SizedBox(height: 22.0),

              // Titre de la section
              tips.isNotEmpty ? Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Astuces",

                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.brightness == Brightness.dark ? Colors.white : Colors.black,
                  )
                )
              ) : const SizedBox.shrink(),

              tips.isNotEmpty ? const SizedBox(height: 18.0) : const SizedBox.shrink(),

              // Cartes avec les astuces
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: tips.length,
                itemBuilder: (BuildContext context, int index) {
                  return Card(
                    child: ListTile(
                      subtitle: Text(tips[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            tips.removeAt(index);
                            box.write('tips', tips);                         
                          });
                        },
                      ),
                    ),
                  );
                } 
              ),

              tips.isNotEmpty ? const SizedBox(height: 18.0) : const SizedBox.shrink(),

              // Titre de la section
              historic.isNotEmpty ? Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Accéder à vos précédents envois",

                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.brightness == Brightness.dark ? Colors.white : Colors.black,
                  )
                )
              ) : const SizedBox.shrink(),

              historic.isNotEmpty ? const SizedBox(height: 18.0) : const SizedBox.shrink(),

              // Cartes avec les précédents envois
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: historic.length,
                itemBuilder: (BuildContext context, int index) {
                  debugPrint(historic[index].toString());

                  return Card(
                    child: ListTile(
                      title: Text(historic[index]["filename"], overflow: TextOverflow.ellipsis, maxLines: 3),
                      subtitle: Text("${formatDate(historic[index]["date"])} ― ${formatBytes(historic[index]["filesize"] ?? '0')}${historic[index]["filetype"] != null && historic[index]["filetype"].isNotEmpty ? " ― ${historic[index]["filetype"]}" : ""}"),
                      onLongPress: () {
                        HapticFeedback.lightImpact();

                        final screenSize = MediaQuery.of(context).size;
                        final rect = Rect.fromCenter(
                          center: Offset(screenSize.width / 2, screenSize.height / 2),
                          width: 100,
                          height: 100,
                        );
                        Share.share(historic[index]["access"], sharePositionOrigin: rect);
                      },
                      onTap: () {
                        HapticFeedback.lightImpact();
                        urlController.text = historic[index]["access"];
                        startDownload();
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          HapticFeedback.lightImpact();

                          // Afficher un dialogue pour demander une confirmation
                          showAdaptiveDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog.adaptive(
                                title: const Text("Supprimer cet envoi ?"),
                                content: Text("${Platform.isAndroid ? "Le fichier ne pourra pas être récupérer si vous n'en disposez pas une copie. " : ''}Êtes-vous sûr de vouloir supprimer ce transfert des serveurs ?"),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      HapticFeedback.lightImpact();
                                      Navigator.pop(context);
                                    },
                                    child: const Text("Annuler"),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      HapticFeedback.lightImpact();

                                      // Faire une requête pour supprimer le fichier
                                      var response = await dio.delete(
                                        "${historic[index]["apiurl"]}/files/delete",
                                        options: Options(
                                          headers: { 'Content-Type': 'application/json' },
                                        ),
                                        queryParameters: {
                                          "sharekey": historic[index]["sharekey"] ?? "",
                                          "deletekey": historic[index]["deletekey"] ?? ""
                                        },
                                      );

                                      // On supprime l'élément de la liste (même si la requête a échoué, ptet la clé a expiré et donc ça va forcément fail mais on veut le masquer)
                                      setState(() {
                                        historic.removeAt(index);
                                        box.write('historic', historic);
                                      });

                                      // On parse le JSON et affiche l'erreur si le status code n'est pas 200
                                      if (!mounted) return;
                                      if (response.statusCode != 200) {
                                        try {
                                          showSnackBar(context, response.data["message"] ?? response.data["error"] ?? "Impossible de supprimer le transfert");
                                        } catch (e) {
                                          showSnackBar(context, "Impossible de supprimer le transfert");
                                        }
                                      }

                                      // Fermer le dialogue
                                      Navigator.pop(context);
                                    },
                                    child: const Text("Supprimer"),
                                  ),
                                ],
                              );
                            }
                          );
                        },
                      ),
                    ),
                  );
                } 
              )
            ],
          ),
        ),
      )
    );
	}

  void _onQRViewCreated(QRViewController qrController) {
    this.qrController = qrController;
    qrController.scannedDataStream.listen((scanData) {
      setState(() {
        if (lastScannedCode == scanData.code) return;
        lastScannedCode = scanData.code;

        if (scanData.code != null && scanData.code!.isNotEmpty && scanData.code!.length > 3 && scanData.code!.length < 256){
          setState(() {
            urlController.text = scanData.code!;
          });

          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }

          startDownload();
        }
      });
    });
  }
}