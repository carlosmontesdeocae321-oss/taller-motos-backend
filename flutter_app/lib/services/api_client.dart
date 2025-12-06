import 'package:dio/dio.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ApiClient {
  final Dio dio;

  ApiClient(String baseUrl)
      : dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: Duration(milliseconds: 15000),
          receiveTimeout: Duration(milliseconds: 30000),
        ));

  Future<List<dynamic>> getMotos() async {
    final resp = await dio.get('/motos');
    return resp.data as List<dynamic>;
  }

  Future<List<dynamic>> getServices() async {
    final resp = await dio.get('/services');
    return resp.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createMoto(Map<String, dynamic> body) async {
    final resp = await dio.post('/motos', data: body);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMoto(
      int id, Map<String, dynamic> body) async {
    final resp = await dio.put('/motos/$id', data: body);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteMoto(int id) async {
    final resp = await dio.delete('/motos/$id');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createClient(Map<String, dynamic> body) async {
    final resp = await dio.post('/clients', data: body);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateClient(
      int id, Map<String, dynamic> body) async {
    final resp = await dio.put('/clients/$id', data: body);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteClient(int id) async {
    final resp = await dio.delete('/clients/$id');
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createService(Map<String, dynamic> body) async {
    final resp = await dio.post('/services', data: body);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createServiceWithImage(
      Map<String, dynamic> body, String imagePath) async {
    final fileName = p.basename(imagePath);
    final form = FormData.fromMap({
      ...body,
      'image': await MultipartFile.fromFile(imagePath, filename: fileName),
    });
    final resp = await dio.post('/services',
        data: form, options: Options(contentType: 'multipart/form-data'));
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateService(
      int id, Map<String, dynamic> body) async {
    final resp = await dio.put('/services/$id', data: body);
    return resp.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deleteService(int id) async {
    final resp = await dio.delete('/services/$id');
    return resp.data as Map<String, dynamic>;
  }

  Future<String> downloadInvoice(
      int idServicio, String filename, Function(int, int)? onProgress) async {
    final resp = await dio.post('/invoices',
        data: {'id_servicio': idServicio},
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
      if (onProgress != null) onProgress(received, total);
    });

    final bytes = resp.data as List<int>;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<Map<String, dynamic>> createInvoiceForMoto(int idMoto) async {
    final resp = await dio.post('/invoices', data: {'id_moto': idMoto});
    return resp.data as Map<String, dynamic>;
  }

  Future<String> downloadInvoiceForMoto(
      int idMoto, String filename, Function(int, int)? onProgress) async {
    final resp = await dio.post('/invoices',
        data: {'id_moto': idMoto},
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: (received, total) {
      if (onProgress != null) onProgress(received, total);
    });
    final bytes = resp.data as List<int>;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
