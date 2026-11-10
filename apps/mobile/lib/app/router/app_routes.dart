enum AppTab {
  today('/today'),
  sleep('/sleep'),
  heart('/heart'),
  activity('/activity'),
  ring('/ring');

  new(this.path);

  final String path;
}

abstract final class AppPaths {
  static const settings = '/ring/settings';
}
