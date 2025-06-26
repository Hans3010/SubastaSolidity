# SubastaSolidity
Entrega Final Modulo 2 del curso de Solidity
Este proyecto implementa un smart contract para una subasta en la blockchain de Ethereum. El diseño se centra en cumplir los requisitos funcionales del proyecto, garantizando un proceso transparente y seguro para todos los participantes.

#Estructura y Componentes Clave

El estado del contrato se gestiona a través de varias variables clave:

  address public beneficiario: Almacena la dirección de la persona que vende el artículo y que, por tanto, recibirá los fondos de la oferta ganadora.
    
  uint256 public fechaFinalizacion: Guarda la fecha y hora exactas (en formato timestamp de Unix) en que termina la subasta.
    
  address public mayorOferente y uint256 public mayorOferta: Llevan un registro público de quién es el postor con la oferta más alta y cuál es el monto de dicha oferta.
    
  mapping(address => uint256) public depositos: Funciona como una base de datos o libro contable interno. Asocia la dirección de cada participante con la cantidad total de Ether que ha depositado en el contrato. Es la pieza central para gestionar los reembolsos de forma segura y eficiente.
    
  bool public subastaFinalizada: Una variable booleana (true/false) que actúa como un interruptor. Permite controlar qué acciones están permitidas según si la subasta está activa o ya ha concluido.
    
  Ownable de OpenZeppelin: Se importó este contrato estándar para gestionar de forma segura la propiedad del contrato. El owner (quien despliega el contrato) es el único que puede recibir las comisiones generadas.

#Lógica de Funcionamiento (Paso a Paso)

El flujo de ejecución del contrato se divide en tres etapas principales:

1. Inicialización (Constructor)
Al desplegar el contrato, se configuran los parámetros base de la subasta:

    Se define quién es el beneficiario (vendedor).
    Se establece la duración en segundos, que se suma al tiempo actual del bloque para calcular la fechaFinalizacion.
    La dirección que despliega el contrato se establece automáticamente como owner.

2. Realizar una Oferta (ofertar)
Esta es la función principal que los participantes utilizan. Es payable, lo que significa que acepta envíos de Ether. Para que una oferta sea válida, el contrato realiza las siguientes comprobaciones (require):

    Verifica que la subasta todavía esté activa (que subastaFinalizada sea false y que la fecha actual sea menor a fechaFinalizacion).
    Comprueba que el monto enviado sea como mínimo un 5% superior a la mayorOferta actual.
    Funcionalidad Anti-Sniping: Se implementó una lógica para prevenir las ofertas de último segundo. Si una oferta válida se realiza dentro de los últimos 10 minutos, el contrato extiende automáticamente la fechaFinalizacion por 10 minutos más.

3. Finalización de la Subasta (finalizarSubasta)
Una vez que el tiempo se ha agotado, cualquier persona puede llamar a esta función para cerrar formalmente la subasta. Su responsabilidad es:

    Marcar la subasta como finalizada (subastaFinalizada = true).
    Calcular la comisión del 2% sobre la oferta ganadora.
    Transferir los fondos: la comisión al owner del contrato y el monto restante al beneficiario.
