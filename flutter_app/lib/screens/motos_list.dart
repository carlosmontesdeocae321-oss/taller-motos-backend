import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../services/api_client.dart';
import '../models/moto.dart';
import 'moto_detail.dart';

class MotosListScreen extends StatefulWidget {
  final ApiClient apiClient;
  const MotosListScreen({Key? key, required this.apiClient}) : super(key: key);

  @override
  State<MotosListScreen> createState() => _MotosListScreenState();
}

class _MotosListScreenState extends State<MotosListScreen> {
  late Future<List<Moto>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadMotos();
  }

  Future<List<Moto>> _loadMotos() async {
    final list = await widget.apiClient.getMotos();
    return list.map((e) => Moto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadMotos();
    });
  }

  void _openServiceDialog(Moto moto) async {
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
              title: Text('Crear servicio para ${moto.marca} ${moto.modelo}'),
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
                                    if (picked != null) {
                                      fechaCtrl.text = picked
                                          .toIso8601String()
                                          .substring(0, 10);
                                    }
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
                            if (picked != null) {
                              fechaCtrl.text =
                                  picked.toIso8601String().substring(0, 10);
                            }
                          },
                          validator: (v) {
                            if (v == null || v.trim().isEmpty)
                              return 'Fecha requerida';
                            final regex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
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
                                allowedExtensions: ['jpg', 'jpeg', 'png'],
                              );
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
          'id_moto': moto.idMoto,
          'descripcion': descripcion,
          'fecha': fecha,
          'costo': costo,
        };
        if (imagePath != null) {
          await widget.apiClient.createServiceWithImage(body, imagePath);
        } else {
          await widget.apiClient.createService(body);
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Servicio creado')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creando servicio: $e')));
      }
    }
  }

  void _openCreateDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          // client fields
          final nombreCtrl = TextEditingController();
          final telefonoCtrl = TextEditingController();
          final direccionCtrl = TextEditingController();
          // moto fields
          final marcaCtrl = TextEditingController();
          final modeloCtrl = TextEditingController();
          final placaCtrl = TextEditingController();
          final anioCtrl = TextEditingController();

          final _formKey = GlobalKey<FormState>();
          return AlertDialog(
            title: Text('Crear cliente y moto'),
            content: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Datos del cliente',
                            style: TextStyle(fontWeight: FontWeight.bold))),
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
                    SizedBox(height: 12),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Datos de la moto',
                            style: TextStyle(fontWeight: FontWeight.bold))),
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
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancelar')),
              ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState?.validate() ?? false) {
                      Navigator.pop(context, {
                        'cliente': {
                          'nombre': nombreCtrl.text.trim(),
                          'telefono': telefonoCtrl.text.isEmpty
                              ? null
                              : telefonoCtrl.text.trim(),
                          'direccion': direccionCtrl.text.isEmpty
                              ? null
                              : direccionCtrl.text.trim(),
                        },
                        'moto': {
                          'marca': marcaCtrl.text.trim(),
                          'modelo': modeloCtrl.text.trim(),
                          'placa': placaCtrl.text.isEmpty
                              ? null
                              : placaCtrl.text.trim(),
                          'anio': anioCtrl.text.isEmpty
                              ? null
                              : int.tryParse(anioCtrl.text),
                        }
                      });
                    }
                  },
                  child: Text('Crear'))
            ],
          );
        });

    if (result != null) {
      try {
        final cliente = result['cliente'] as Map<String, dynamic>;
        final moto = result['moto'] as Map<String, dynamic>;
        // create client first
        final clientResp = await widget.apiClient.createClient(cliente);
        final idCliente = clientResp['id_cliente'] ?? clientResp['id'] ?? null;
        if (idCliente == null) throw Exception('No se obtuvo id del cliente');
        // attach id_cliente to moto and create
        final motoBody = Map<String, dynamic>.from(moto);
        motoBody['id_cliente'] = idCliente;
        await widget.apiClient.createMoto(motoBody);
        await _refresh();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Cliente y moto creados')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creando cliente/moto: $e')));
      }
    }
  }

  void _openEditMotoDialog(Moto moto) async {
    final marcaCtrl = TextEditingController(text: moto.marca);
    final modeloCtrl = TextEditingController(text: moto.modelo);
    final placaCtrl = TextEditingController(text: moto.placa ?? '');
    final anioCtrl = TextEditingController(text: moto.anio?.toString() ?? '');
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
                          'id_cliente': moto.idCliente,
                          'marca': marcaCtrl.text.trim(),
                          'modelo': modeloCtrl.text.trim(),
                          'anio': anioCtrl.text.isEmpty
                              ? null
                              : int.tryParse(anioCtrl.text),
                          'placa': placaCtrl.text.isEmpty
                              ? null
                              : placaCtrl.text.trim(),
                        };
                        await widget.apiClient.updateMoto(moto.idMoto, body);
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
      await _refresh();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Moto actualizada')));
    }
  }

  void _deleteMoto(Moto moto) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text('Eliminar moto'),
              content: Text('¿Eliminar la moto ${moto.marca} ${moto.modelo}?'),
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
        await widget.apiClient.deleteMoto(moto.idMoto);
        await _refresh();
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Moto eliminada')));
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error eliminando moto: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // try to load logo from backend assets folder: ../assets/logo.png
    Widget titleWidget;
    // Prefer the bundled asset for the logo; fall back to file during desktop dev
    Widget logoWidget;
    try {
      logoWidget = Image.asset('assets/logo.png',
          width: 180, height: 80, fit: BoxFit.contain);
    } catch (e) {
      final logoPath = Directory.current.path + '/../assets/logo.png';
      if (File(logoPath).existsSync()) {
        logoWidget = Image.file(File(logoPath),
            width: 180, height: 80, fit: BoxFit.contain);
      } else {
        logoWidget = SizedBox.shrink();
      }
    }
    titleWidget = Row(
      children: [
        logoWidget,
        SizedBox(width: 12),
        Text('Motos', style: TextStyle(color: Colors.black)),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        centerTitle: false,
      ),
      body: FutureBuilder<List<Moto>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final motos = snap.data ?? [];
          if (motos.isEmpty) return Center(child: Text('No hay motos'));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: motos.length,
              itemBuilder: (context, idx) {
                final m = motos[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12.0, vertical: 6.0),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => MotoDetailScreen(
                                  moto: m, apiClient: widget.apiClient))),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.deepPurple.shade100,
                              child: Text(m.marca.isNotEmpty ? m.marca[0] : '?',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${m.marca} ${m.modelo}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16)),
                                    const SizedBox(height: 6),
                                    Text('Placa: ${m.placa ?? '-'}',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13)),
                                    const SizedBox(height: 4),
                                    Text(
                                        'Cliente: ${m.clienteNombre ?? m.idCliente}',
                                        style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 13)),
                                  ]),
                            ),
                            Column(mainAxisSize: MainAxisSize.min, children: [
                              ElevatedButton.icon(
                                  onPressed: () => _openServiceDialog(m),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Servicio'),
                                  style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      textStyle:
                                          const TextStyle(fontSize: 12))),
                              const SizedBox(height: 8),
                              Row(children: [
                                IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.white70),
                                    onPressed: () => _openEditMotoDialog(m)),
                                IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.redAccent),
                                    onPressed: () => _deleteMoto(m)),
                              ])
                            ])
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: _openCreateDialog,
      ),
    );
  }
}
