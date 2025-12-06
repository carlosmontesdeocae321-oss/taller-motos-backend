class Moto {
  final int idMoto;
  final int idCliente;
  final String marca;
  final String modelo;
  final int? anio;
  final String? placa;
  final String? clienteNombre;

  Moto({
    required this.idMoto,
    required this.idCliente,
    required this.marca,
    required this.modelo,
    this.anio,
    this.placa,
    this.clienteNombre,
  });

  factory Moto.fromJson(Map<String, dynamic> json) {
    return Moto(
      idMoto: json['id_moto'] ?? json['idMoto'] ?? 0,
      idCliente: json['id_cliente'] ?? 0,
      marca: json['marca'] ?? '',
      modelo: json['modelo'] ?? '',
      anio: json['anio'] != null ? int.tryParse(json['anio'].toString()) : null,
      placa: json['placa'],
      clienteNombre: json['cliente_nombre'],
    );
  }
}
