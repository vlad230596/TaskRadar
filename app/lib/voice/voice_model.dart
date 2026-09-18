import 'package:flutter/foundation.dart';

/// The speech model this app dictates with (F9), and why it is this one.
///
/// ## GigaAM v3, NeMo CTC, with punctuation
///
/// GigaAM is Salute Developers' (Sber's) open Russian ASR model; k2-fsa
/// publishes converted ONNX builds of it alongside `sherpa_onnx`, which is how
/// it gets here without anyone writing onnxruntime bindings by hand.
///
/// The variant is the **punctuated** v3 CTC export. The migration plan expected
/// to ship without punctuation and to look into restoring it later ("ASR отдаёт
/// поток слов без знаков препинания"); that turned out to be unnecessary --
/// there is a build in the same family, at the same download size, that emits
/// punctuation and capitalisation itself. For a task title it hardly matters;
/// for a dictated note it is the difference between a sentence and a telegram.
///
/// CTC rather than the transducer build of the same model: the two are within a
/// few megabytes and a few percent of each other in accuracy, and CTC is the
/// simpler decoder with the shorter tail on a phone.
///
/// ## Why it is not in the APK
///
/// 225 MB unpacked. Shipping it inside the app would make every build and every
/// sideloaded update a quarter of a gigabyte, for a feature that not every
/// installation will use -- the desktop client has a keyboard. So it is fetched
/// on first use into application-support storage and can be deleted again from
/// Settings, which is also the honest way to present a cost that large: as
/// something the user agrees to.
///
/// ## Licence -- checked, and better than the plan assumed
///
/// The plan flagged the converted sherpa-onnx models as non-commercial and said
/// the fact had to be recorded deliberately rather than stumbled into. Recorded:
/// **GigaAM is MIT** (`salute-developers/GigaAM`, "Copyright (c) 2024 GigaChat
/// Team"), and the model repository carries the same MIT text. The
/// non-commercial restriction belonged to an earlier release of the weights. For
/// a personal tool it made no difference either way; for the record, there is no
/// restriction to work around.
@immutable
class VoiceModel {
  const VoiceModel({
    required this.id,
    required this.name,
    required this.archiveUrl,
    required this.downloadBytes,
    required this.installedBytes,
  });

  /// Directory name on disk. Changing it means "a different model", and the old
  /// one is simply no longer found -- which is the correct behaviour, because
  /// the recogniser cannot mix files from two exports.
  final String id;

  /// What the settings screen calls it.
  final String name;

  /// Where the archive comes from.
  ///
  /// A GitHub release asset, pinned to an exact file name rather than a
  /// "latest" redirect: a model that silently changed under a running
  /// installation would change what the microphone produces, and the tokens
  /// file and the graph have to match each other exactly.
  final String archiveUrl;

  /// Compressed size, for the "this will cost you 156 MB" dialogue.
  final int downloadBytes;

  /// Size on disk after unpacking, which is the number that actually matters to
  /// someone deciding whether to keep it.
  final int installedBytes;

  /// The model the app uses. There is deliberately no picker: a second option
  /// would be a setting nobody can make an informed choice about.
  static const VoiceModel gigaAmV3Punct = VoiceModel(
    id: 'sherpa-onnx-nemo-ctc-punct-giga-am-v3-russian-2025-12-16',
    name: 'GigaAM v3 (русский, со знаками препинания)',
    archiveUrl:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
        'sherpa-onnx-nemo-ctc-punct-giga-am-v3-russian-2025-12-16.tar.bz2',
    downloadBytes: 163 * 1000 * 1000,
    installedBytes: 236 * 1000 * 1000,
  );
}

/// A model that is present on disk and ready to be loaded.
@immutable
class InstalledVoiceModel {
  const InstalledVoiceModel({
    required this.model,
    required this.modelPath,
    required this.tokensPath,
    required this.bytesOnDisk,
  });

  final VoiceModel model;

  /// The ONNX graph (`model.int8.onnx` in every build published so far).
  final String modelPath;

  /// `tokens.txt`, which has to come from the same export as [modelPath].
  final String tokensPath;

  final int bytesOnDisk;
}

/// What the app can say about dictation right now.
sealed class VoiceModelState {
  const VoiceModelState();
}

/// This build cannot dictate at all, and no amount of downloading would change
/// that.
///
/// The web build, and only it. The recogniser is `sherpa_onnx` over
/// onnxruntime reading a 225 MB model out of application-support storage, and a
/// browser tab has neither that storage nor a way to hold the weights; the
/// microphone package would work, the two halves behind it would not.
///
/// A state of its own rather than [VoiceModelMissing] because the two produce
/// different screens: "missing" offers a download button, and offering a
/// download that cannot succeed is the worst of the three possible answers.
class VoiceModelUnsupported extends VoiceModelState {
  const VoiceModelUnsupported();
}

/// Nobody has looked on disk yet.
///
/// Distinct from [VoiceModelMissing] because the two produce different screens:
/// "checking" must not offer a 163 MB download for something that is already
/// there, and a microphone button that appears and then vanishes on every cold
/// start is worse than one that appears a frame late.
class VoiceModelUnknown extends VoiceModelState {
  const VoiceModelUnknown();
}

/// The model has not been downloaded (or was deleted).
class VoiceModelMissing extends VoiceModelState {
  const VoiceModelMissing({this.lastError});

  /// Why the last attempt to install it failed, if there was one. Null on a
  /// clean "never asked for it".
  final String? lastError;
}

/// Downloading or unpacking.
class VoiceModelInstalling extends VoiceModelState {
  const VoiceModelInstalling({
    required this.receivedBytes,
    required this.totalBytes,
    required this.unpacking,
  });

  final int receivedBytes;
  final int totalBytes;

  /// The download is done and the archive is being unpacked -- a separate phase
  /// because it takes tens of seconds on a phone and reports no progress of its
  /// own. A bar that sat at 100% in silence would look like a hang.
  final bool unpacking;

  double? get fraction =>
      totalBytes <= 0 ? null : (receivedBytes / totalBytes).clamp(0.0, 1.0);
}

/// Installed and usable.
class VoiceModelReady extends VoiceModelState {
  const VoiceModelReady(this.installed);

  final InstalledVoiceModel installed;
}
