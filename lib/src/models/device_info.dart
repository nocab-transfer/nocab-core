class DeviceInfo {
  late String name;
  late String ip;
  late int requestPort;
  late String opsystem;

  DeviceInfo({required this.name, required this.ip, required this.requestPort, required this.opsystem});

  DeviceInfo.fromJson(Map<String, dynamic> json) {
    name = json['name'];
    ip = json['ip'];
    requestPort = json['requestPort'];
    opsystem = json['opsystem'];
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['name'] = name;
    data['ip'] = ip;
    data['requestPort'] = requestPort;
    data['opsystem'] = opsystem;
    return data;
  }
}
