import 'package:flutter/material.dart';
import '../models/moto.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
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
  late Future<List<dynamic>> _servicesFuture;
  int _downloadingServiceId = -1;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _servicesFuture = _loadServices();
  }

  Future<List<dynamic>> _loadServices() async {
    final list = await widget.apiClient.getServices();
    // filter by moto id
    return list.where((e) {
      try {
        return (e['id_moto']?.toString() ?? '') ==
            widget.moto.idMoto.toString();
      } catch (ex) {
        return false;
      }
    }).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _servicesFuture = _loadServices();
    });
  }

  Future<void> _downloadAndOpen(int idServicio) async {
    setState(() {
      _downloadingServiceId = idServicio;
      _downloadProgress = 0.0;
    });
    final filename = 'factura_${idServicio}.pdf';
    try {
      final path = await widget.apiClient.downloadInvoice(idServicio, filename,
          (received, total) {
        setState(() {
          if (total != 0) _downloadProgress = received / total;
        });
      });
      // open the file
      await OpenFile.open(path);
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error descargando factura: $err')));
    } finally {
      setState(() {
        _downloadingServiceId = -1;
        _downloadProgress = 0.0;
      });
    }
  }

  void _openServiceDialog() async {
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
              title: Text(
                  'Crear servicio para ${widget.moto.marca} ${widget.moto.modelo}'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                          controller: descCtrl,
                          decoration: InputDecoration(labelText: 'Descripción'),
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
                          decoration: InputDecoration(
                              labelText: 'Fecha (YYYY-MM-DD)',
                              suffixIcon: IconButton(
                                  icon: Icon(Icons.calendar_today),
                                  onPressed: () async {
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
                                      fechaCtrl.text = picked
                                          .toIso8601String()
                                          .substring(0, 10);
                                  })),
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
                          },
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Fecha requerida';
                            final regex = RegExp(r'^\d{4}-\d{2}-\d{2}\$');
                            if (!regex.hasMatch(v)) return 'Formato YYYY-MM-DD';
                            return null;
                          }),
                      SizedBox(height: 12),
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
                          },
                        ),
                        SizedBox(width: 12),
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
          'costo': costo,
        };
        if (imagePath != null) {
          // Upload image to Cloudinary (signed) then create service with returned secure_url
          try {
            final file = File(imagePath);
            final uploadRes =
                await widget.apiClient.uploadToCloudinarySigned(file);
            final secureUrl = uploadRes['secure_url'] as String?;
            if (secureUrl != null) body['image_path'] = secureUrl;
            await widget.apiClient.createService(body);
          } catch (e) {
            // Fallback: try to create service using the backend multipart endpoint
            try {
              await widget.apiClient.createServiceWithImage(body, imagePath);
            } catch (e2) {
              throw Exception(
                  'Error subiendo imagen: $e ; fallback error: $e2');
            }
          }
        } else {
          await widget.apiClient.createService(body);
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Servicio creado')));
        await _refresh();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creando servicio: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('${widget.moto.marca} ${widget.moto.modelo}'),
          actions: [
            IconButton(
                icon: Icon(Icons.receipt_long),
                onPressed: () async {
                  try {
                    setState(() {
                      _downloadingServiceId = -2;
                      _downloadProgress = 0.0;
                    });
                    final filename = 'factura_moto_${widget.moto.idMoto}.pdf';
                    final path = await widget.apiClient.downloadInvoiceForMoto(
                        widget.moto.idMoto, filename, (received, total) {
                      setState(() {
                        if (total != 0) _downloadProgress = received / total;
                      });
                    });
                    await OpenFile.open(path);
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Factura generada')));
                  } catch (err) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Error generando factura: $err')));
                  } finally {
                    setState(() {
                      _downloadingServiceId = -1;
                      _downloadProgress = 0.0;
                    });
                  }
                }),
            IconButton(icon: Icon(Icons.edit), onPressed: _editMoto),
            IconButton(icon: Icon(Icons.delete), onPressed: _deleteMoto),
          ]),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(
                        'Cliente: ${widget.moto.clienteNombre ?? widget.moto.idCliente}',
                        style: TextStyle(fontSize: 18))),
                IconButton(
                    icon: Icon(Icons.edit, size: 20), onPressed: _editClient),
                IconButton(
                    icon: Icon(Icons.delete, size: 20, color: Colors.redAccent),
                    onPressed: _deleteClient),
              ],
            ),
            SizedBox(height: 8),
            Text('Año: ${widget.moto.anio ?? '-'}'),
            SizedBox(height: 8),
            Text('Placa: ${widget.moto.placa ?? '-'}'),
            SizedBox(height: 20),
            Text('Servicios',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: _servicesFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting)
                    return Center(child: CircularProgressIndicator());
                  if (snap.hasError)
                    return Center(child: Text('Error: ${snap.error}'));
                  final services = snap.data ?? [];
                  if (services.isEmpty)
                    return Center(
                        child: Text('No hay servicios para esta moto'));
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      itemCount: services.length,
                      itemBuilder: (context, idx) {
                        final s = services[idx] as Map<String, dynamic>;
                        final id = s['id_servicio'];
                        final rawDate = s['fecha'] as String?;
                        final dateOnly = _formatDate(rawDate);
                        final costo = s['costo'] != null
                            ? double.tryParse(s['costo'].toString()) ?? 0.0
                            : 0.0;
                        final completed = (s['completed'] == 1 ||
                            s['completed'] == true ||
                            s['completed'] == '1');
                        final imagePath = s['image_path'] as String?;
                        final imageUrl = imagePath != null
                            ? (imagePath.startsWith('http')
                                ? imagePath
                                : (widget.apiClient.dio.options.baseUrl +
                                    imagePath))
                            : null;
                        return Card(
                          color: completed ? Colors.grey[200] : null,
                          margin: EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: imageUrl != null
                                ? GestureDetector(
                                    onTap: () async {
                                      try {
                                        await widget.apiClient.updateService(
                                            id, {'completed': !completed});
                                        await _refresh();
                                      } catch (err) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    'Error actualizando servicio: $err')));
                                      }
                                    },
                                    child: CircleAvatar(
                                      radius: 28,
                                      backgroundColor: completed
                                          ? Colors.green.shade100
                                          : Colors.deepPurple.shade50,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(28),
                                        child: Image.network(imageUrl,
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover),
                                      ),
                                    ),
                                  )
                                : null,
                            title: Text(
                              s['descripcion'] ?? '',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                decoration: completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              'Fecha: $dateOnly  •  Precio: \$${costo.toStringAsFixed(2)}',
                              style: TextStyle(
                                  decoration: completed
                                      ? TextDecoration.lineThrough
                                      : null),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // toggle complete
                                // edit service
                                IconButton(
                                  icon:
                                      Icon(Icons.edit, color: Colors.blueGrey),
                                  onPressed: () async {
                                    await _editService(
                                        s as Map<String, dynamic>);
                                  },
                                ),
                                // delete
                                IconButton(
                                  icon: Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                              title: Text('Eliminar servicio'),
                                              content: Text(
                                                  '¿Eliminar este servicio?'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, false),
                                                    child: Text('Cancelar')),
                                                ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(c, true),
                                                    child: Text('Eliminar'))
                                              ],
                                            ));
                                    if (ok == true) {
                                      try {
                                        await widget.apiClient
                                            .deleteService(id);
                                        await _refresh();
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    'Servicio eliminado')));
                                      } catch (err) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(
                                                content: Text(
                                                    'Error eliminando servicio: $err')));
                                      }
                                    }
                                  },
                                ),
                                _downloadingServiceId == id
                                    ? SizedBox(
                                        width: 80,
                                        child: LinearProgressIndicator(
                                            value: _downloadProgress))
                                    : ElevatedButton(
                                        onPressed: () => _downloadAndOpen(id),
                                        child: Text('Factura'))
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: _openServiceDialog,
      ),
    );
  }

  void _editMoto() async {
    // reuse a dialog similar to motos_list edit
    final marcaCtrl = TextEditingController(text: widget.moto.marca);
    final modeloCtrl = TextEditingController(text: widget.moto.modelo);
    final placaCtrl = TextEditingController(text: widget.moto.placa ?? '');
    final anioCtrl =
        TextEditingController(text: widget.moto.anio?.toString() ?? '');
    final _formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Editar moto'),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                        controller: marcaCtrl,
                        decoration: InputDecoration(labelText: 'Marca'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Marca requerida'
                            : null),
                    TextFormField(
                        controller: modeloCtrl,
                        decoration: InputDecoration(labelText: 'Modelo'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Modelo requerido'
                            : null),
                    TextFormField(
                        controller: placaCtrl,
                        decoration: InputDecoration(labelText: 'Placa')),
                    TextFormField(
                        controller: anioCtrl,
                        decoration: InputDecoration(labelText: 'Año'),
                        keyboardType: TextInputType.number),
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
                    if (_formKey.currentState?.validate() ?? false) {
                      try {
                        final body = {
                          'id_cliente': widget.moto.idCliente,
                          'marca': marcaCtrl.text.trim(),
                          'modelo': modeloCtrl.text.trim(),
                          'anio': anioCtrl.text.isEmpty
                              ? null
                              : int.tryParse(anioCtrl.text),
                          'placa': placaCtrl.text.isEmpty
                              ? null
                              : placaCtrl.text.trim(),
                        };
                        await widget.apiClient
                            .updateMoto(widget.moto.idMoto, body);
                        Navigator.pop(context, true);
                      } catch (e) {
                        Navigator.pop(context, false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Error actualizando moto: $e')));
                      }
                    }
                  },
                  child: Text('Guardar'))
            ],
          );
        });

    if (result == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Moto actualizada')));
      // Refresh parent screens by popping and reopening detail from updated data could be implemented; for now just refresh services
      setState(() {});
    }
  }

  void _deleteMoto() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text('Eliminar moto'),
              content: Text('¿Eliminar esta moto?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text('Cancelar')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text('Eliminar'))
              ],
            ));
    if (ok == true) {
      try {
        await widget.apiClient.deleteMoto(widget.moto.idMoto);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Moto eliminada')));
        Navigator.pop(context); // go back to list
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error eliminando moto: $e')));
      }
    }
  }

  void _editClient() async {
    // Need client id; moto has idCliente
    final nombreCtrl =
        TextEditingController(text: widget.moto.clienteNombre ?? '');
    final telefonoCtrl = TextEditingController();
    final direccionCtrl = TextEditingController();
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
                    if (_formKey.currentState?.validate() ?? false) {
                      try {
                        final body = {
                          'nombre': nombreCtrl.text.trim(),
                          'telefono': telefonoCtrl.text.isEmpty
                              ? null
                              : telefonoCtrl.text.trim(),
                          'direccion': direccionCtrl.text.isEmpty
                              ? null
                              : direccionCtrl.text.trim(),
                        };
                        await widget.apiClient
                            .updateClient(widget.moto.idCliente, body);
                        Navigator.pop(context, true);
                      } catch (e) {
                        Navigator.pop(context, false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Error actualizando cliente: $e')));
                      }
                    }
                  },
                  child: Text('Guardar'))
            ],
          );
        });

    if (result == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Cliente actualizado')));
      setState(() {});
    }
  }

  void _deleteClient() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text('Eliminar cliente'),
              content: Text(
                  '¿Eliminar al cliente? Esto eliminará también las motos asociadas.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text('Cancelar')),
                ElevatedButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text('Eliminar'))
              ],
            ));
    if (ok == true) {
      try {
        await widget.apiClient.deleteClient(widget.moto.idCliente);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Cliente eliminado')));
        Navigator.pop(context); // back to list
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error eliminando cliente: $e')));
      }
    }
  }

  Future<void> _editService(Map<String, dynamic> s) async {
    final id = s['id_servicio'];
    final descCtrl = TextEditingController(text: s['descripcion'] ?? '');
    final costoCtrl = TextEditingController(text: s['costo']?.toString() ?? '');
    final fechaCtrl = TextEditingController(
        text: (s['fecha'] as String?)?.substring(0, 10) ??
            DateTime.now().toIso8601String().substring(0, 10));
    final _formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text('Editar servicio'),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                        controller: descCtrl,
                        decoration: InputDecoration(labelText: 'Descripción'),
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
                        },
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Fecha requerida';
                          final regex = RegExp(r'^\d{4}-\d{2}-\d{2}\$');
                          if (!regex.hasMatch(v)) return 'Formato YYYY-MM-DD';
                          return null;
                        }),
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
                    if (_formKey.currentState?.validate() ?? false) {
                      try {
                        final body = {
                          'id_moto': s['id_moto'],
                          'descripcion': descCtrl.text.trim(),
                          'fecha': fechaCtrl.text.trim(),
                          'costo': double.tryParse(
                                  costoCtrl.text.replaceAll(',', '.')) ??
                              0.0,
                        };
                        await widget.apiClient.updateService(id, body);
                        Navigator.pop(context, true);
                      } catch (e) {
                        Navigator.pop(context, false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Error actualizando servicio: $e')));
                      }
                    }
                  },
                  child: Text('Guardar'))
            ],
          );
        });

    if (result == true) {
      await _refresh();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Servicio actualizado')));
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return '-';
    try {
      // If it's already in YYYY-MM-DD or contains T or space, extract first part
      // Try ISO-like first
      if (raw.contains('T')) {
        final date = raw.split('T')[0];
        final dt = DateTime.parse(date);
        return _weekdayNameSpanish(dt.weekday) +
            ' ' +
            dt.toIso8601String().substring(0, 10);
      }
      // If contains a yyyy-mm-dd anywhere, use that
      final isoMatch = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(raw);
      if (isoMatch != null) {
        final dateStr = isoMatch.group(1)!;
        final dt = DateTime.parse(dateStr);
        return _weekdayNameSpanish(dt.weekday) + ' ' + dateStr;
      }
      // If it's a simple date string of length >= 10
      if (raw.length >= 10) {
        try {
          final dt = DateTime.parse(raw.substring(0, 10));
          return _weekdayNameSpanish(dt.weekday) +
              ' ' +
              dt.toIso8601String().substring(0, 10);
        } catch (_) {}
      }
      // If it starts with an English short weekday like 'Sat' or 'Mon', replace with Spanish
      final shortMatch =
          RegExp(r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)', caseSensitive: false)
              .firstMatch(raw);
      if (shortMatch != null) {
        final en = shortMatch.group(1)!;
        final es = _weekdayShortToSpanish(en);
        return raw.replaceFirst(RegExp(en, caseSensitive: false), es);
      }
      // fallback: try parsing generically
      final dt = DateTime.parse(raw);
      return _weekdayNameSpanish(dt.weekday) +
          ' ' +
          dt.toIso8601String().substring(0, 10);
    } catch (e) {
      return raw;
    }
  }

  String _weekdayNameSpanish(int weekday) {
    // DateTime.weekday: 1 = Monday ... 7 = Sunday
    switch (weekday) {
      case DateTime.monday:
        return 'Lunes';
      case DateTime.tuesday:
        return 'Martes';
      case DateTime.wednesday:
        return 'Miércoles';
      case DateTime.thursday:
        return 'Jueves';
      case DateTime.friday:
        return 'Viernes';
      case DateTime.saturday:
        return 'Sábado';
      case DateTime.sunday:
        return 'Domingo';
      default:
        return '';
    }
  }

  String _weekdayShortToSpanish(String en) {
    final key = en.substring(0, 3).toLowerCase();
    switch (key) {
      case 'mon':
        return 'Lun';
      case 'tue':
        return 'Mar';
      case 'wed':
        return 'Mié';
      case 'thu':
        return 'Jue';
      case 'fri':
        return 'Vie';
      case 'sat':
        return 'Sáb';
      case 'sun':
        return 'Dom';
      default:
        return en;
    }
  }
}
