// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Subasta
 * @author Hans
 * @notice Este contrato gestiona una subasta simple con funcionalidades avanzadas como
 * extensión de tiempo anti-sniping y reembolsos parciales.
 * El creador del contrato (Hans) recibe una comisión del 2% sobre la oferta ganadora.
 */
contract Subasta is Ownable {

    // =================================================================================
    //                                  Variables de Estado
    // =================================================================================

    address payable public beneficiario; 
    uint256 public fechaFinalizacion;  

    address public mayorOferente;      
    uint256 public mayorOferta;     

    mapping(address => uint256) public depositos;

    address[] private oferentes;
    mapping(address => bool) private esOferente; 

    bool public subastaFinalizada;   

    uint256 private constant COMISION_PORCENTAJE = 2; 


    // =================================================================================
    //                                      Eventos
    // =================================================================================

    /**
     * @notice Se emite cuando un participante realiza una nueva oferta válida.
     * @param oferente La dirección de la persona que oferta.
     * @param monto El valor de la nueva oferta.
     */
    event NuevaOferta(address indexed oferente, uint256 monto);

    /**
     * @notice Se emite cuando la subasta finaliza oficialmente.
     * @param ganador La dirección del ganador de la subasta.
     * @param montoFinal El monto de la oferta ganadora.
     */
    event SubastaFinalizada(address ganador, uint256 montoFinal);

    /**
     * @notice Se emite cuando un usuario retira fondos.
     * @param usuario La dirección del usuario que retira.
     * @param monto El valor retirado.
     */
    event FondosRetirados(address indexed usuario, uint256 monto);


    // =================================================================================
    //                                     Modificadores
    // =================================================================================

    modifier soloMientrasActiva() {
        require(!subastaFinalizada, "La subasta ya ha finalizado.");
        _;
    }

    modifier soloDespuesDeFinalizar() {
        require(subastaFinalizada, "La subasta aun no ha finalizado.");
        _;
    }


    // =================================================================================
    //                                     Constructor
    // =================================================================================

    /**
     * @notice Inicializa la subasta.
     * @param _beneficiario La dirección que recibirá los fondos del artículo subastado.
     * @param _duracionEnSegundos La duración inicial de la subasta en segundos.
     */
    constructor(address payable _beneficiario, uint256 _duracionEnSegundos) Ownable(msg.sender) {
        require(_beneficiario != address(0), "La direccion del beneficiario no puede ser la direccion cero.");
        require(_duracionEnSegundos > 0, "La duracion debe ser mayor a cero.");

        beneficiario = _beneficiario;
        fechaFinalizacion = block.timestamp + _duracionEnSegundos;
    }


    // =================================================================================
    //                                Funcionalidades Principales
    // =================================================================================

    /**
     * @notice Permite a un usuario realizar una oferta. La función es 'payable',
     * lo que significa que debe ser llamada con un envío de Ether.
     */
    function ofertar() external payable soloMientrasActiva {
        uint256 ofertaMinimaRequerida = mayorOferta + (mayorOferta * 5 / 100);
        if (mayorOferta == 0) {
            ofertaMinimaRequerida = 1 wei;
        }
        
        require(msg.value >= ofertaMinimaRequerida, "La oferta debe ser al menos 5% mayor que la actual.");
        require(block.timestamp < fechaFinalizacion, "La subasta ha expirado.");

        if (block.timestamp >= fechaFinalizacion - 10 minutes) {
            fechaFinalizacion += 10 minutes;
        }
 
        mayorOferente = msg.sender;
        mayorOferta = msg.value;
        depositos[msg.sender] += msg.value;

        if (!esOferente[msg.sender]) {
            esOferente[msg.sender] = true;
            oferentes.push(msg.sender);
        }

        emit NuevaOferta(msg.sender, msg.value);
    }

    /**
     * @notice Finaliza la subasta, transfiere los fondos al beneficiario y la comisión al dueño.
     * Solo puede ser llamada después de que el tiempo de la subasta haya transcurrido.
     */
    function finalizarSubasta() external {
        require(block.timestamp >= fechaFinalizacion, "La subasta aun no puede finalizar.");
        require(!subastaFinalizada, "La subasta ya fue finalizada.");

        subastaFinalizada = true;

        if (mayorOferente != address(0)) {
            uint256 comision = (mayorOferta * COMISION_PORCENTAJE) / 100;
            uint256 montoParaBeneficiario = mayorOferta - comision;

            (bool successComision, ) = owner().call{value: comision}("");
            require(successComision, "Fallo al enviar la comision al owner.");

            (bool successBeneficiario, ) = beneficiario.call{value: montoParaBeneficiario}("");
            require(successBeneficiario, "Fallo al enviar fondos al beneficiario.");

            depositos[mayorOferente] -= mayorOferta;
        }

        emit SubastaFinalizada(mayorOferente, mayorOferta);
    }

    /**
     * @notice Permite a los oferentes que no ganaron retirar el total de sus depósitos
     * una vez que la subasta ha finalizado.
     */
    function retirarFondosPerdedor() external soloDespuesDeFinalizar {
        uint256 monto = depositos[msg.sender];
        require(monto > 0, "No tienes fondos para retirar.");
        // El ganador no puede usar esta función para retirar. Su depósito sobrante (si lo hubiera)
        // puede ser retirado con `reembolsoParcial`.
        require(msg.sender != mayorOferente, "El ganador no puede retirar fondos de esta manera.");

        // Re-entrancy guard: Poner a cero el balance ANTES de enviar.
        depositos[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: monto}("");
        require(success, "Fallo al retirar los fondos.");

        emit FondosRetirados(msg.sender, monto);
    }


    // =================================================================================
    //                            Funcionalidades Avanzadas
    // =================================================================================
    
    /**
     * @notice Permite a cualquier oferente retirar los fondos que ha depositado
     * por encima de la oferta ganadora actual. Un perdedor puede retirar todo su depósito,
     * y el actual ganador puede retirar cualquier cantidad que haya depositado en ofertas anteriores.
     * Esta función puede ser llamada durante o después de la subasta.
     */
    function reembolsoParcial() external {
        uint256 montoARetirar;
        uint256 miDepositoTotal = depositos[msg.sender];
        require(miDepositoTotal > 0, "No tienes depositos en el contrato.");

        if (msg.sender == mayorOferente) {
            montoARetirar = miDepositoTotal - mayorOferta;
        } else {
            montoARetirar = miDepositoTotal;
        }
        
        require(montoARetirar > 0, "No tienes fondos excedentes para retirar.");
        
        depositos[msg.sender] -= montoARetirar;

        (bool success, ) = msg.sender.call{value: montoARetirar}("");
        require(success, "Fallo al retirar el reembolso parcial.");

        emit FondosRetirados(msg.sender, montoARetirar);
    }


    // =================================================================================
    //                               Funciones de Vista (Lectura)
    // =================================================================================

    /**
     * @notice Devuelve el ganador y el monto ganador una vez finalizada la subasta.
     * @return ganador La dirección del oferente ganador.
     * @return monto El valor de la oferta ganadora.
     */
    function mostrarGanador() external view soloDespuesDeFinalizar returns (address ganador, uint256 monto) {
        return (mayorOferente, mayorOferta);
    }

    /**
     * @notice Devuelve la lista de todos los oferentes y sus depósitos totales actuales.
     * @return _oferentes Array de direcciones de los oferentes.
     * @return _depositos Array de los montos depositados por cada oferente.
     */
    function mostrarOfertas() external view returns (address[] memory _oferentes, uint256[] memory _depositos) {
        uint256 cantidadOferentes = oferentes.length;
        _oferentes = new address[](cantidadOferentes);
        _depositos = new uint256[](cantidadOferentes);

        for (uint i = 0; i < cantidadOferentes; i++) {
            address oferente = oferentes[i];
            _oferentes[i] = oferente;
            _depositos[i] = depositos[oferente];
        }

        return (_oferentes, _depositos);
    }

    /**
     * @notice Devuelve el estado actual de la subasta.
     * @return _mayorOferente El postor más alto actual.
     * @return _mayorOferta La oferta más alta actual.
     * @return _fechaFinalizacion El timestamp de finalización.
     * @return _subastaFinalizada Si la subasta ha terminado.
     * @return _balanceContrato El balance total de Ether en el contrato.
     */
    function getEstadoSubasta() external view returns (
        address _mayorOferente,
        uint256 _mayorOferta,
        uint256 _fechaFinalizacion,
        bool _subastaFinalizada,
        uint256 _balanceContrato
    ) {
        return (
            mayorOferente,
            mayorOferta,
            fechaFinalizacion,
            subastaFinalizada,
            address(this).balance
        );
    }
}
