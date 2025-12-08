// Moto detail screen: show moto info, list services for this moto and allow
// generating invoice PDFs for a single service or for the whole moto.
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';

import '../models/moto.dart';
import '../services/api_client.dart';

class MotoDetailScreen extends StatefulWidget {
  final Moto moto;
  final ApiClient apiClient;
  const MotoDetailScreen(
      {Key? key, required this.moto, required this.apiClient})
      : super(key: key);

  @override
  State<MotoDetailScreen> createState() => _MotoDetailScreenState();
}

class _MotoDetailScreenState extends State<MotoDetailScreen> {
  late Future<List<Map<String, dynamic>>> _futureServices;
  Map<String, dynamic>? _clientData;

  @override
  void initState() {
    super.initState();
    _futureServices = _loadServices();
    _loadClient();
  }

  Future<void> _loadClient() async {
    try {
      final data = await widget.apiClient.getClient(widget.moto.idCliente);
      setState(() {
        _clientData = data;
      });
    } catch (e) {
      // ignore; we'll show name from moto if fetch fails
    }
  }

  String _absImageUrl(String url) {
    String base = widget.apiClient.dio.options.baseUrl;
    if (base.isEmpty) base = 'http://localhost:3000';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/'))
      return base.endsWith('/')
          ? base.substring(0, base.length - 1) + url
          : base + url;
    return base.endsWith('/') ? base + url : base + '/' + url;
  }

  void _openImageViewer(String url) {
    final abs = _absImageUrl(url);
    showDialog(
        context: context,
        builder: (ctx) {
          return Dialog(
            insetPadding: const EdgeInsets.all(12.0),
            child: Container(
              width: double.infinity,
              height: MediaQuery.of(context).size.height * 0.8,
              color: Colors.black,
              child: Stack(
                children: [
                  Center(
                    child: InteractiveViewer(
                      panEnabled: true,
                      minScale: 1.0,
                      maxScale: 5.0,
                      child: Image.network(
                        abs,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image,
                            size: 96,
                            color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ))
                ],
              ),
            ),
          );
        });
  }

  Future<List<Map<String, dynamic>>> _loadServices() async {
    final all = await widget.apiClient.getServices();
    final list = (all.cast<Map<String, dynamic>>()).where((s) {
      final id = s['id_moto'] ?? s['idMoto'] ?? s['id_moto'];
      return id == widget.moto.idMoto;
    }).toList();
    // sort by fecha desc
    list.sort((a, b) {
      final fa = (a['fecha'] ?? '').toString();
      final fb = (b['fecha'] ?? '').toString();
      return fb.compareTo(fa);
    });
    return list;
  }

  Future<void> _refresh() async {
    setState(() {
      _futureServices = _loadServices();
    });
  }

  Future<void> _downloadInvoiceForService(int idServicio) async {
    final snack = ScaffoldMessenger.of(context);
    final filename = 'factura_servicio_${idServicio}.pdf';
    try {
      snack.showSnackBar(const SnackBar(content: Text('Generando factura...')));
      final path = await widget.apiClient
          .downloadInvoice(idServicio, filename, (r, t) {});
      snack.showSnackBar(SnackBar(content: Text('Factura guardada en: $path')));
      await OpenFile.open(path);
    } catch (e) {
      String msg = e.toString();
      if (e is DioException) {
        try {
          final resp = e.response?.data;
          if (resp != null) msg = resp is String ? resp : resp.toString();
        } catch (_) {}
      }
      snack.showSnackBar(
          SnackBar(content: Text('Error generando factura: $msg')));
    }
  }

  Future<void> _downloadInvoiceForMoto() async {
    final snack = ScaffoldMessenger.of(context);
    final filename = 'factura_moto_${widget.moto.idMoto}.pdf';
    try {
      snack.showSnackBar(
          const SnackBar(content: Text('Generando factura para la moto...')));
      final path = await widget.apiClient
          .downloadInvoiceForMoto(widget.moto.idMoto, filename, (r, t) {});
      snack.showSnackBar(SnackBar(content: Text('Factura guardada en: $path')));
      await OpenFile.open(path);
    } catch (e) {
      String msg = e.toString();
      if (e is DioException) {
        try {
          final resp = e.response?.data;
          if (resp != null) msg = resp is String ? resp : resp.toString();
        } catch (_) {}
      }
      snack.showSnackBar(
          SnackBar(content: Text('Error generando factura: $msg')));
    }
  }

  Future<void> _openCreateServiceDialog() async {
    final descCtrl = TextEditingController();
    final costoCtrl = TextEditingController();
    final fechaCtrl = TextEditingController(
        text: DateTime.now().toIso8601String().substring(0, 10));
    final _formKey = GlobalKey<FormState>();
    String? pickedImagePath;

    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              title: Text('Crear servicio'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        TextFormField(
                          controller: descCtrl,
                          decoration: InputDecoration(labelText: 'Descripción'),
                          keyboardType: TextInputType.multiline,
                          minLines: 3,
                          maxLines: 8,
                          textInputAction: TextInputAction.newline,
                          validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Descripción requerida'
                            : null),
                      TextFormField(
                          controller: costoCtrl,
                          decoration: InputDecoration(labelText: 'Costo'),
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Costo requerido';
                            final n = double.tryParse(v.replaceAll(',', '.'));
                            if (n == null) return 'Número inválido';
                            if (n <= 0) return 'Debe ser mayor que 0';
                            return null;
                          }),
                      TextFormField(
                          controller: fechaCtrl,
                          decoration:
                              InputDecoration(labelText: 'Fecha (YYYY-MM-DD)'),
                          readOnly: true,
                          onTap: () async {
                            DateTime initial = DateTime.now();
                            try {
                              initial = DateTime.parse(fechaCtrl.text);
                            } catch (_) {}
                            final picked = await showDatePicker(
                                context: context,
                                initialDate: initial,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100));
                            if (picked != null)
                              fechaCtrl.text =
                                  picked.toIso8601String().substring(0, 10);
                          }),
                      const SizedBox(height: 12),
                      Row(children: [
                        ElevatedButton.icon(
                            icon: Icon(Icons.attach_file),
                            label: Text(pickedImagePath == null
                                ? 'Adjuntar foto'
                                : 'Cambiar foto'),
                            onPressed: () async {
                              try {
                                final res = await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['jpg', 'jpeg', 'png']);
                                if (res != null && res.files.isNotEmpty) {
                                  setState(() {
                                    pickedImagePath = res.files.first.path;
                                  });
                                }
                              } catch (e) {
                                print('Error picking file: $e');
                              }
                            }),
                        const SizedBox(width: 12),
                        if (pickedImagePath != null)
                          SizedBox(
                              width: 80,
                              height: 60,
                              child: Image.file(File(pickedImagePath!),
                                  fit: BoxFit.cover)),
                      ])
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancelar')),
                ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState?.validate() ?? false) {
                        Navigator.pop(context, {
                          'descripcion': descCtrl.text.trim(),
                          'costo': costoCtrl.text.trim(),
                          'fecha': fechaCtrl.text.trim(),
                          'imagePath': pickedImagePath,
                        });
                      }
                    },
                    child: Text('Crear'))
              ],
            );
          });
        });

    if (result != null) {
      try {
        final descripcion = result['descripcion'] as String? ?? '';
        final costoStr = result['costo'] as String? ?? '0';
        final fecha = result['fecha'] as String? ??
            DateTime.now().toIso8601String().substring(0, 10);
        final costo = double.tryParse(costoStr.replaceAll(',', '.')) ?? 0.0;
        final imagePath = result['imagePath'] as String?;
        final body = {
          'id_moto': widget.moto.idMoto,
          'descripcion': descripcion,
          'fecha': fecha,
          'costo': costo
        };
        if (imagePath != null) {
          await widget.apiClient.createServiceWithImage(body, imagePath);
        } else {
          await widget.apiClient.createService(body);
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Servicio creado')));
        await _refresh();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creando servicio: $e')));
      }
    }
  }

  Future<void> _openEditServiceDialog(Map<String, dynamic> s) async {
    final id = s['id_servicio'] as int? ?? s['id_servicio'] as int?;
    if (id == null) return;
    final descripcionCtrl =
        TextEditingController(text: s['descripcion']?.toString() ?? '');
    final costoCtrl =
        TextEditingController(text: (s['costo'] ?? '').toString());
    final fechaCtrl = TextEditingController(
        text: (s['fecha'] ?? '').toString().substring(0, 10));
    final _formKey = GlobalKey<FormState>();

    List<String> existing = [];
    if (s['image_path'] != null &&
        s['image_path'].toString().trim().isNotEmpty) {
      existing = s['image_path']
          .toString()
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final toRemove = <String>{};
    final List<String> pickedNew = [];

    final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              title: Text('Editar servicio'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        TextFormField(
                          controller: descripcionCtrl,
                          decoration: InputDecoration(labelText: 'Descripción'),
                          keyboardType: TextInputType.multiline,
                          minLines: 3,
                          maxLines: 8,
                          textInputAction: TextInputAction.newline,
                          validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Descripción requerida'
                            : null),
                      TextFormField(
                          controller: costoCtrl,
                          decoration: InputDecoration(labelText: 'Costo'),
                          keyboardType:
                              TextInputType.numberWithOptions(decimal: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Costo requerido';
                            final n = double.tryParse(v.replaceAll(',', '.'));
                            if (n == null) return 'Número inválido';
                            return null;
                          }),
                      TextFormField(
                          controller: fechaCtrl,
                          decoration:
                              InputDecoration(labelText: 'Fecha (YYYY-MM-DD)'),
                          readOnly: true,
                          onTap: () async {
                            DateTime initial = DateTime.now();
                            try {
                              initial = DateTime.parse(fechaCtrl.text);
                            } catch (_) {}
                            final picked = await showDatePicker(
                                context: context,
                                initialDate: initial,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100));
                            if (picked != null)
                              fechaCtrl.text =
                                  picked.toIso8601String().substring(0, 10);
                          }),
                      const SizedBox(height: 12),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Fotos existentes',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      const SizedBox(height: 8),
                      if (existing.isEmpty) const Text('- ninguna -'),
                      Wrap(
                          children: existing.map((url) {
                        final removed = toRemove.contains(url);
                        return Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Stack(
                            children: [
                              SizedBox(
                                  width: 100,
                                  height: 80,
                                  child: Image.network(_absImageUrl(url),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Icon(Icons.broken_image))),
                              Positioned(
                                  top: 0,
                                  right: 0,
                                  child: IconButton(
                                      icon: Icon(
                                          removed ? Icons.undo : Icons.delete,
                                          color: removed
                                              ? Colors.green
                                              : Colors.redAccent),
                                      onPressed: () {
                                        setState(() {
                                          if (removed)
                                            toRemove.remove(url);
                                          else
                                            toRemove.add(url);
                                        });
                                      })),
                            ],
                          ),
                        );
                      }).toList()),
                      const SizedBox(height: 8),
                      Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Agregar nuevas fotos',
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                          icon: Icon(Icons.add_a_photo),
                          label: Text('Seleccionar fotos'),
                          onPressed: () async {
                            try {
                              final res = await FilePicker.platform.pickFiles(
                                  allowMultiple: true,
                                  type: FileType.custom,
                                  allowedExtensions: ['jpg', 'jpeg', 'png']);
                              if (res != null && res.files.isNotEmpty) {
                                setState(() {
                                  for (var f in res.files)
                                    if (f.path != null) pickedNew.add(f.path!);
                                });
                              }
                            } catch (e) {
                              print('pick error $e');
                            }
                          }),
                      const SizedBox(height: 8),
                      Wrap(
                          children: pickedNew
                              .map((p) => Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: SizedBox(
                                      width: 100,
                                      height: 80,
                                      child: Image.file(File(p),
                                          fit: BoxFit.cover))))
                              .toList()),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Cancelar')),
                ElevatedButton(
                    onPressed: () async {
                      if (!(_formKey.currentState?.validate() ?? false)) return;
                      Navigator.pop(context, true);
                    },
                    child: Text('Guardar'))
              ],
            );
          });
        });

    if (result == true) {
      // prepare preserved images
      List<String> preserved =
          existing.where((e) => !toRemove.contains(e)).toList();
      final desc = descripcionCtrl.text.trim();
      final costo = double.tryParse(costoCtrl.text.replaceAll(',', '.')) ?? 0.0;
      final fecha = fechaCtrl.text.trim();
      final snack = ScaffoldMessenger.of(context);
      try {
        // Try uploading new files directly to Cloudinary (signed) to get URLs
        final List<String> newUrls = [];
        for (final p in pickedNew) {
          try {
            final uploadResp =
                await widget.apiClient.uploadToCloudinarySigned(File(p));
            if (uploadResp.containsKey('secure_url'))
              newUrls.add(uploadResp['secure_url']);
            else if (uploadResp.containsKey('url'))
              newUrls.add(uploadResp['url']);
          } catch (e) {
            // on any failure, fallback to server multipart flow
            // perform fallback sequentially: send current preserved as body then upload file
            String currentPreserved = preserved.join(',');
            final body = {
              'descripcion': desc,
              'costo': costo,
              'fecha': fecha,
              'image_path': currentPreserved
            };
            await widget.apiClient.updateServiceWithImage(id, body, p);
            // fetch updated service to obtain image_path for next iteration
            final srv = await widget.apiClient.getService(id);
            final ip = srv['image_path'] ?? '';
            preserved = ip
                .toString()
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          }
        }

        if (newUrls.isNotEmpty) {
          final finalList = [...preserved, ...newUrls];
          final body = {
            'descripcion': desc,
            'costo': costo,
            'fecha': fecha,
            'image_path': finalList.join(',')
          };
          await widget.apiClient.updateService(id, body);
        } else {
          // if all uploads used fallback, we already updated via updateServiceWithImage; ensure other fields updated
          final body = {
            'descripcion': desc,
            'costo': costo,
            'fecha': fecha,
            'image_path': preserved.join(',')
          };
          await widget.apiClient.updateService(id, body);
        }

        snack.showSnackBar(
            const SnackBar(content: Text('Servicio actualizado')));
        await _refresh();
      } catch (e) {
        snack.showSnackBar(
            SnackBar(content: Text('Error actualizando servicio: $e')));
      }
    }
  }

  Future<void> _deleteService(int id) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text('Eliminar servicio'),
                content: Text('¿Eliminar este servicio?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text('Cancelar')),
                  ElevatedButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text('Eliminar'))
                ]));
    if (ok == true) {
      try {
        await widget.apiClient.deleteService(id);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Servicio eliminado')));
        await _refresh();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error eliminando servicio: $e')));
      }
    }
  }

  Future<void> _openEditClientDialog() async {
    // fetch current client data if we don't have it
    Map<String, dynamic> client = _clientData ?? {};
    try {
      if (_clientData == null)
        client = await widget.apiClient.getClient(widget.moto.idCliente);
    } catch (e) {
      // ignore
    }

    final nombreCtrl = TextEditingController(text: client['nombre'] ?? '');
    final telefonoCtrl = TextEditingController(text: client['telefono'] ?? '');
    final direccionCtrl =
        TextEditingController(text: client['direccion'] ?? '');
    final _formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Editar cliente'),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                        controller: nombreCtrl,
                        decoration: InputDecoration(labelText: 'Nombre'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nombre requerido'
                            : null),
                    TextFormField(
                        controller: telefonoCtrl,
                        decoration: InputDecoration(labelText: 'Teléfono')),
                    TextFormField(
                        controller: direccionCtrl,
                        decoration: InputDecoration(labelText: 'Dirección')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancelar')),
              ElevatedButton(
                  onPressed: () async {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    Navigator.pop(context, true);
                  },
                  child: Text('Guardar'))
            ],
          );
        });

    if (result == true) {
      try {
        final body = {
          'nombre': nombreCtrl.text.trim(),
          'telefono': telefonoCtrl.text.trim().isEmpty
              ? null
              : telefonoCtrl.text.trim(),
          'direccion': direccionCtrl.text.trim().isEmpty
              ? null
              : direccionCtrl.text.trim(),
        };
        await widget.apiClient.updateClient(widget.moto.idCliente, body);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Cliente actualizado')));
        await _loadClient();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error actualizando cliente: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${widget.moto.marca} ${widget.moto.modelo}'),
          const SizedBox(height: 4),
          Text(
              'Placa: ${widget.moto.placa ?? '-'}  •  Año: ${widget.moto.anio?.toString() ?? '-'}',
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Generar factura (moto)',
            onPressed: _downloadInvoiceForMoto,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        'Cliente: ${_clientData != null ? (_clientData!['nombre'] ?? widget.moto.clienteNombre) : (widget.moto.clienteNombre ?? widget.moto.idCliente)}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                        '${_clientData != null && (_clientData!['telefono'] ?? '').toString().isNotEmpty ? 'Tel: ${_clientData!['telefono']}' : ''}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                        '${_clientData != null && (_clientData!['direccion'] ?? '').toString().isNotEmpty ? 'Dirección: ${_clientData!['direccion']}' : ''}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ])),
              IconButton(
                  icon: Icon(Icons.edit, size: 20),
                  tooltip: 'Editar cliente',
                  onPressed: _openEditClientDialog)
            ]),
            const SizedBox(height: 12),
            const Text('Servicios',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _futureServices,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  if (snap.hasError)
                    return Center(
                        child: Text('Error cargando servicios: ${snap.error}'));
                  final items = snap.data ?? [];
                  if (items.isEmpty)
                    return const Center(
                        child: Text('No hay servicios para esta moto'));
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, idx) {
                        final s = items[idx];
                        final descripcion = s['descripcion'] ?? '-';
                        final fecha =
                            (s['fecha'] ?? '').toString().substring(0, 10);
                        final costo = (s['costo'] ?? 0).toString();
                        final id = s['id_servicio'] ?? s['id_servicio'];
                        // show images (if any)
                        List<String> images = [];
                        if (s['image_path'] != null &&
                            s['image_path'].toString().trim().isNotEmpty) {
                          images = s['image_path']
                              .toString()
                              .split(',')
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList();
                        }
                        return ListTile(
                          title: Text(descripcion.toString(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Fecha: $fecha  •  Precio: $costo', style: const TextStyle(fontSize: 13)),
                                if (images.isNotEmpty) SizedBox(height: 8),
                                if (images.isNotEmpty)
                                  SizedBox(
                                      height: 80,
                                      child: ListView.separated(
                                          scrollDirection: Axis.horizontal,
                                          itemBuilder: (_, i) => AspectRatio(
                                              aspectRatio: 4 / 3,
                                              child: Padding(
                                                  padding: const EdgeInsets.only(
                                                      right: 6.0),
                                                  child: InkWell(
                                                      onTap: () => _openImageViewer(
                                                          images[i]),
                                                      child: Image.network(
                                                          _absImageUrl(
                                                              images[i]),
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) =>
                                                              Icon(Icons.broken_image))))),
                                          separatorBuilder: (_, __) => SizedBox(width: 6),
                                          itemCount: images.length))
                              ]),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf,
                                    color: Colors.blueGrey),
                                tooltip: 'Generar factura (servicio)',
                                onPressed: () {
                                  if (id != null)
                                    _downloadInvoiceForService(id as int);
                                },
                              ),
                              IconButton(
                                  icon:
                                      Icon(Icons.edit, color: Colors.blueGrey),
                                  onPressed: () {
                                    _openEditServiceDialog(s);
                                  }),
                              IconButton(
                                  icon: Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  onPressed: () {
                                    if (id != null) _deleteService(id as int);
                                  }),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: _openCreateServiceDialog,
      ),
    );
  }
}
